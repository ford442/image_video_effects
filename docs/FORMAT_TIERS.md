# Internal Texture Format Tiers (#1008)

## Problem

Internal sim/display textures are **`rgba32float`** at up to **2048²** with multiple ping-pong targets (`write`, `dataA/B/C`, `history`, `read`, `source`). That is quality-correct for HDR sims and multi-pass feedback, but roughly **4×** the bandwidth of `rgba16float` for pure visual effects.

Memory sketch (order of magnitude, 2048²):

| Target count | rgba32float | rgba16float |
|--------------|-------------|-------------|
| 1× | ~64 MiB | ~32 MiB |
| ~6 storage/sampled rgba targets | ~384 MiB | ~192 MiB |

Adaptive resolution scaling alone cannot save integrated GPUs when format bandwidth dominates.

## Design decision: storage demotion, not present-only

**Present is already cheap.** The canvas blit targets `bgra8unorm` (browser preferred format). Demoting only the present path saves ~0 MiB.

**Storage demotion is where the savings are.** All internal rgba targets in [`src/renderer/webgpu/resources.ts`](../src/renderer/webgpu/resources.ts) share one tier-selected format. Depth textures remain **`r32float`** (wave height, RD concentrations in depth channel).

WGSL sources in `public/shaders/` stay authored as **`rgba32float`** canonical. The host rewrites storage declarations at pipeline compile time for non-ultra tiers (see [`src/renderer/wgslFormatRewrite.ts`](../src/renderer/wgslFormatRewrite.ts)).

## Quality tiers

| Tier | `colorFormat` | Typical scale | Use |
|------|---------------|---------------|-----|
| `ultra` | `rgba32float` | 1.0× | Desktop discrete, physics sims — **bit-compatible with pre-tiering sims** |
| `balanced` | `rgba16float` | 0.75× | Default laptop / modern iGPU |
| `battery` | `rgba16float` | 0.5× | Mobile / thermal |
| `auto` | probe-driven | adaptive | FP16 on integrated/mobile; FP32 on discrete |

**`compat` (`rgba8unorm`) — Phase 2.** Many shaders use HDR, negative intermediates, and alpha > 1. Not enabled in the initial rollout.

## Physics / precision guard

Shaders that need full FP32 storage (reaction-diffusion concentrations, fluid state, wave sims) may declare:

```json
"requiresRgba32Float": true
```

When such a shader is loaded, the host records it and **pins the internal storage format to
`rgba32float`** — the user's quality tier (scale, slot cap, pass cap) is left alone. The pin is
resolved by `resolveFp32Pin()` in [`src/config/formatPolicy.ts`](../src/config/formatPolicy.ts)
and re-applied on every tier change, so switching to balanced/battery **after** loading a sim
cannot silently demote it. Category `simulation` and tags `physics` / `reaction-diffusion` /
`fluid` are inferred as FP32-required when the flag is omitted.

`RendererManager.getPerformanceStatus()` reports `requestedColorFormat` (what the tier asked
for), `colorFormat` (what is actually allocated), `fp32Pinned` and `fp32PinnedBy`. The render
quality panel shows a **⚠ FP32 pinned** badge whenever they disagree. Call
`releaseFp32Requirement(id)` when such a shader is unloaded so the format can drop back to FP16.

Do **not** silently run physics sims at FP16.

## Host rewrite contract

Bindings rewritten (storage write only):

| Binding | WGSL name | Ultra | Balanced / Battery |
|---------|-----------|-------|-------------------|
| 2 | `writeTexture` | `rgba32float` | `rgba16float` |
| 7 | `dataTextureA` | `rgba32float` | `rgba16float` |
| 8 | `dataTextureB` | `rgba32float` | `rgba16float` |
| 6 | `writeDepthTexture` | `r32float` | `r32float` (unchanged) |

Pipeline cache keys include `colorFormat`. Tier changes destroy textures, rebuild bind-group layout, and clear the shader cache.

**Fail-soft:** `rewriteWgslStorageFormatsChecked()` reports any `rgba*` storage declaration the
rewrite could not bring onto the tier format (unusual spelling, `read_write` access, a format we
do not tier). Compilation continues with the partially rewritten source — strictly closer to the
allocated textures than the original — and the miss is recorded in
`getFormatRewriteWarnings()` and logged, instead of surfacing as an opaque pipeline-creation
failure. A non-empty warning list is a bug: fix the shader or widen the rewrite.

## Capability probe

At device init ([`src/renderer/webgpu/device.ts`](../src/renderer/webgpu/device.ts)):

- `adapter.info` GPU type: discrete / integrated / cpu
- `float32-filterable` (existing)
- `maxTextureDimension2D` (existing)

Resolved in [`src/config/formatPolicy.ts`](../src/config/formatPolicy.ts).

## C++ WASM parity

[`wasm_renderer/resources.cpp`](../wasm_renderer/resources.cpp) and [`wasm_renderer/pipeline.cpp`](../wasm_renderer/pipeline.cpp) use the same tier mapping via [`wasm_renderer/performance_policy.h`](../wasm_renderer/performance_policy.h). WGSL rewrite runs in TypeScript before `loadShader()` passes source to C++.

## Benchmarking

`__pixelocity__.runBenchmark(frames, { qualityMode })` (under `?testMode=1`) reports
`colorFormat`, `requestedColorFormat`, `fp32Pinned`, `estimatedTextureMiB`, `internalWidth/Height`,
`scale`, `maxPassesPerFrame`, `avgFps`, `avgTotalMs`, `timingSource` and `hasRealGpuTimings`.

The sweep is automated:

```bash
npm run build
WASM_GPU_TESTS=1 npx playwright test tests/format-tier-bench.spec.ts   # or: npm run bench:format-tiers
```

It sweeps `ultra` / `balanced` / `battery` over five workload shapes
([`tests/fixtures/formatTierMatrix.ts`](../tests/fixtures/formatTierMatrix.ts)) — simple
generative, feedback fluid, the `ripple-tank` Tier C graph, a 3-slot chain, and a history-ring
temporal shader — and writes `reports/format-tier-bench-<date>.md` plus
`test-results/format-tier-bench.json`.

**Adapter reality check.** Cloud and headless CI VMs cannot observe a WebGPU adapter, so the spec
writes a stub report (`GPU observed: no`) and skips. Numbers from such a run are not evidence.
Real runs come from a human machine or a self-hosted GPU runner via Actions →
**GPU_REQUIRED (manual)** ([`.github/workflows/gpu-required.yml`](../.github/workflows/gpu-required.yml)).

Fill in hardware, sim spot-checks, thermal notes and the go/no-go verdict by hand using
[`reports/format-tier-bench-TEMPLATE.md`](../reports/format-tier-bench-TEMPLATE.md).

Priority shaders for ad-hoc comparison: `sim-fluid-feedback-coupled`, `gen-lichen-reaction-diffusion`, `plasma`.

## `compat` (rgba8unorm) — Phase 2, design only

Not implemented, and **not** to be implemented until the bench above says balanced is
insufficient on the slowest supported iGPU. Recorded here so the design is not re-derived:

- **Saving:** 4 bytes/px vs 8 (FP16) vs 16 (FP32) — another ~50% off FP16 storage.
- **Blocker:** `rgba8unorm` clamps to `[0, 1]`. Shaders using HDR intermediates, negative values
  (velocity/vorticity fields, signed distance in a data channel) or alpha > 1 break silently —
  the visual result stays plausible, which is the worst failure mode.
- **Would require:** an explicit per-shader opt-in flag (`compatSafe: true`) covering the whole
  ping-pong chain, not a global tier — the rewrite is not a safe blanket transform here.
- **Would also require:** encode/decode helpers for shaders that need signed data in a compat
  target, plus a bind-group storage-format check, since `rgba8unorm` storage textures are not
  universally supported for `write` access.
- **Trigger to revisit:** a bench row where balanced still misses 30 FPS on an integrated adapter
  at scale 0.5 and the bottleneck is demonstrably bandwidth (texture MiB scaling tracks FPS).

## Related

- [`docs/BINDING_CONTRACT.md`](BINDING_CONTRACT.md) — bind-group layout; storage format is tier-dependent at runtime
- [`src/config/performancePolicy.ts`](../src/config/performancePolicy.ts) — scale, slots, passes + `colorFormat`
- MEMORY.md — "don't downgrade rgba32float without tiering"
