# Layer compositor

Per-slot blend, opacity and masks for the TS WebGPU renderer (#1512 Part B). Without it, parallel slots were "last wins" and a chained slot replaced its input outright. Every slot now has a **layer** that says how its output joins the image under it.

The WASM backend is frozen ([WASM_BACKEND_POLICY.md](WASM_BACKEND_POLICY.md)) and ignores layers. The UI row is disabled there.

## Model

`src/renderer/layerState.ts` (pure, no GPU):

| Field | Values | Default |
| --- | --- | --- |
| `output` | `replace` · `blend` · `mask` | `replace` |
| `blend` | `normal`, `add`, `screen`, `multiply`, `overlay`, `soft-light`, `difference`, `luma-key`, `depth-key` | `normal` |
| `opacity` | 0–1 | 1 |
| `mask` | `{ source: 'none' \| 'luma' \| 'depth' \| 'slot', slot?, invert?, feather? }` | none |
| `key` | key threshold 0–1 (`luma-key` 0.08, `depth-key` 0.5 when absent) | — |

- **replace** keeps the old behaviour exactly: a frame whose slots are all replace layers compiles to the same frame plan as before, and the compositor allocates nothing.
- **blend** mixes the slot's output over the image below by `opacity × mask` using the blend mode.
- **mask** renders the slot only as a matte for other slots' masks. It adds no colour.

All blending is in **linear light**, in the internal colour format (`rgba16float` / `rgba32float`), which is the convention the present pass already assumes. Values above 1.0 survive to an HDR canvas. `screen` uses the HDR-safe form `a + b − sat(a)·sat(b)`. `overlay` and `soft-light` work on saturated values and carry the excess above 1.0 through. The keys use a `smoothstep` of width `KEY_SOFTNESS` (0.04) around the threshold, on the layer's luma (`luma-key`) or the depth map (`depth-key`).

### Masks

A masked layer's mask is drawn into its own `r8unorm` layer before the composite:

- `luma`: the luma of the slot's own output
- `depth`: the depth map (binding 4); 0 when no depth map is loaded
- `slot` N: another slot's output, captured earlier in the same frame. If that slot's output is `mask`, its luma is the matte; otherwise its alpha is.
- `invert` flips the matte. `feather` (0–1; radius up to `FEATHER_MAX_RADIUS_PX` = 24 px at a 1024-row working size, scaled with it) runs a separable 13-tap gaussian.

A mask that references a slot which has not rendered yet this frame (a later chained slot) draws unmasked, with a one-time console warning.

## Frame plan

`src/renderer/webgpu/compositorPlan.ts` adds two ops to the frame-plan IR ([BINDING_CONTRACT.md](BINDING_CONTRACT.md), `framePlan.ts`):

- `captureLayer`: copy a slot's output (writeTex) into a layer of the stack
- `composite`: blend a group of captured layers over the base (readTex) into writeTex

What gets compiled:

- **Parallel group** with any non-replace member: every member is captured after it runs, then one composite runs before the usual writeTex → readTex copy. That one dispatch reads all members at internal precision.
- **Chained slot** with a non-replace layer: captured, then composited over its own input, which readTex still holds.
- Any slot another slot's mask references is captured too.

Captures get one stack layer per slot (at most 6), so a mask can reference any earlier slot. The op sequence is pinned by `compositorPlan.test.ts`.

## GPU side

`src/renderer/webgpu/compositor.ts` (`LayerCompositor`) with shaders in `public/shaders/_compositor/` (bundled through `?raw`; not catalog shaders and never in the shader lists):

| Shader | Kind | Writes |
| --- | --- | --- |
| `composite.wgsl` | compute 16×16 | writeTex (storage format rewritten to the active tier) |
| `mask.wgsl` | fullscreen render pass | the layer's `r8unorm` mask (r8unorm is not a core storage format) |
| `feather.wgsl` | two render passes (x, y) through a scratch layer | the layer's mask |

- **Allocation.** The stack (2d-array, internal format) and the mask array (2d-array `r8unorm`) are allocated on the first frame that composites. They only grow, until the working size or colour format changes. The stack is refused above `COMPOSITOR_STACK_BUDGET_BYTES` (384 MiB): that frame renders as replace, with a warning. When no slot has a non-replace layer, the textures are released.
- **No per-frame churn.** Bind groups are cached against the textures they hold. Per-op parameters are 256-byte uniform blocks addressed by dynamic offset.
- **Compat devices** need `textureBindingViewDimension: '2d-array'` at creation and must bind every layer; `compat.ts` handles that ([DEVICE_FEATURES.md](DEVICE_FEATURES.md)).
- **Profiling.** Passes are timed as kind `composite` (pink in the pass flame strip). `getDiagnostics().webgpu.compositor` reports `{ layers, bytes, compositesLastFrame }`.

`src/renderer/testing/compositorReference.ts` is a CPU mirror of `composite.wgsl`. A change to a blend formula must land in both, in the same commit: the unit tests and the golden frames compare against it.

## API and automation

- Renderer / manager / worker: `setSlotLayer(index, layer)`, `getSlotLayer(index)`. Layers stay with the slot across shader changes. Test harness: `__pixelocity__.setSlotLayer` / `getSlotLayer`.
- **Opacity is automatable.** The slot param `opacity` (`LAYER_OPACITY_PARAM`, labelled "Layer Opacity") routes to the layer, so MIDI, OSC and audio bindings can drive it like any other slot param.
- **UI.** Controls → Slot stack shows one row per slot (`SlotLayerRow`): a chained/parallel toggle, a blend dropdown (Replace, the nine modes, Mask), an opacity slider, and a mask picker (none, luma, depth, another slot, each optionally inverted). Feather and key thresholds are set through the API, links and project files, not the row.

## Persistence

- **Project files** (schema v2, [VJ_STUDIO.md](VJ_STUDIO.md)) store each slot's layer in its compact form. A v1 file migrates by its version number alone (`migrateV1ToV2`): a slot without layer fields is a replace layer, so it renders as before.
- **Chain links** (`layerChainShare.ts`) carry the same compact fields per slot:

  | Field | Meaning |
  | --- | --- |
  | `b` | blend mode, or `mask` (absent = replace) |
  | `o` | opacity (absent = 1) |
  | `m` | mask reference: `[!](l\|d\|s0–s5)[~feather]`, e.g. `l`, `!d~0.25`, `s2` |
  | `k` | key threshold |

  Unknown values degrade to the defaults, so a link made by a newer build still opens.
- **Device loss / worker crash.** `RendererManager` mirrors every slot's layer and mode and replays them to the new backend, together with the depth map, source auto-exposure, node scales and recent ripples ([RENDER_WORKER.md](RENDER_WORKER.md)).

## Tests

- Unit: `layerState.test.ts`, `compositorPlan.test.ts`, `compositor.test.ts` (packing, encode sequence, no churn, budget, naga validation of all three shaders in both tiers), `WebGPURenderer.compositor.test.ts`, the project and chain-link tests.
- Golden frames: `tests/compositor-golden.swiftshader.spec.ts` renders two solid-colour parallel slots under every blend mode at 50%, at `rgba16float` and `rgba32float`, and compares the readback with the reference (`src/renderer/testing/goldenTolerance.ts`, ±3 per channel). Run it with `npm run test:engine2 -- compositor-golden` on SwiftShader, or with the `compositor-golden` suite of the manual GPU workflow (`.github/workflows/gpu-required.yml`, Playwright project `gpu-golden`) on a real adapter.
