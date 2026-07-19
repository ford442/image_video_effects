# Multipass Graph (Tier C)

Declarative **intra-frame** compute graphs for iterative sims (Jacobi, wave steps, cloth constraints).

Extends Tier B linear chains ([`multipassRegistry.ts`](../src/renderer/multipassRegistry.ts)) with same-frame texture handoff, loop counts, and pass budgets.

**Related:**
- Bind group layout: [`docs/BINDING_CONTRACT.md`](BINDING_CONTRACT.md)
- Sim texture packing: [`agents/swarm-tasks/advanced-physics/MULTIPASS_SIM_CONTRACT.md`](../agents/swarm-tasks/advanced-physics/MULTIPASS_SIM_CONTRACT.md)
- Builder: [`scripts/buildMultipassRegistry.js`](../scripts/buildMultipassRegistry.js)
- Validator: [`src/renderer/multipassGraph.ts`](../src/renderer/multipassGraph.ts)
- Executor: [`src/renderer/GraphRunner.ts`](../src/renderer/GraphRunner.ts)

## Tier comparison

| Tier | Mechanism | Same-frame handoff | Loops |
|------|-----------|-------------------|-------|
| A | Single-pass shader | — | — |
| B | `multipass.nextShader` linear chain | No (1-frame latency via `dataC`) | — |
| C | `multipass.graph` + `GraphRunner` | Yes (copy barriers + rebind) | `repeat` |

## JSON schema (primary catalog entry)

Secondary WGSL files are referenced by `entry` id only — no separate JSON.

```json
{
  "id": "wave-tank",
  "url": "shaders/wave-step.wgsl",
  "multipass": {
    "graph": {
      "maxPassesPerFrame": 8,
      "nodes": [
        { "id": "step",   "entry": "wave-step",   "reads": ["dataC"], "writes": ["dataA"], "repeat": 3 },
        { "id": "inject", "entry": "wave-inject", "reads": ["dataA"], "writes": ["dataB"] },
        { "id": "render", "entry": "wave-render", "reads": ["dataB"], "writes": ["color", "dataA"] }
      ]
    }
  }
}
```

### Node fields

| Field | Required | Description |
|-------|----------|-------------|
| `id` | yes | Stable node name (logging) |
| `entry` | yes | WGSL shader id (`public/shaders/<entry>.wgsl`) |
| `reads` | yes | Texture roles sampled this dispatch |
| `writes` | yes | Texture roles written this dispatch |
| `repeat` | no | Dispatch count (default `1`, max `64`) |

Tier B `pass` / `nextShader` fields may coexist on the same shader for catalog compatibility; when `graph` is present, the graph runner takes precedence.

## Texture roles

Maps to the immutable 14-entry bind group — **no new bind groups in v1**.

| JSON role | Binding | WGSL name | Physical texture |
|-----------|---------|-----------|------------------|
| `read` | 1 | `readTexture` | `readTex` (source image) |
| `color` | 2 | `writeTexture` | `writeTex` (display output) |
| `dataA` | 7 | `dataTextureA` | `dataTexA` (storage) |
| `dataB` | 8 | `dataTextureB` | `dataTexB` (storage) |
| `dataC` | 9 | `dataTextureC` | `dataTexC` (sampled prev-frame / handoff) |

`reads` / `writes` declare roles **touched** by the entry shader (validation + copy planning), not separate dispatches per role.

## Repeat expansion

- `repeat: 1` — one dispatch.
- `repeat: N` (`N > 1`) — `N` dispatches of the same `entry`.
- Between iterations that read `dataC` after writing `dataA` or `dataB`, the host inserts **`dataA → dataC`** or **`dataB → dataC`** copy barriers so WGSL can keep sampling binding 9.
- When a node writes both `dataA` and `dataB` with `repeat > 1`, iterations alternate the primary write target (ping-pong).

## Copy-barrier rules

The executor tracks the latest producer per sim role (`dataA`, `dataB`, `dataC`).

Before each dispatch, insert `encoder.copyTextureToTexture` when:

1. **Storage → sample:** dispatch reads `dataC` but the latest write was `dataA` or `dataB` (bindings 7/8 → 9).
2. **Cross-buffer:** dispatch reads `dataB` via `dataC` but latest write was `dataA` (or vice versa) — copy writer → `dataC`.
3. **Repeat iteration:** second and later iterations of a `repeat` node that reads `dataC` after writing `dataA`/`dataB`.

Copies use the scaled internal resolution (`scaledW` × `scaledH`).

## Pass budget

Total dispatches = `sum(node.repeat ?? 1)` per frame.

Capped by:

```
effectiveCap = min(graph.maxPassesPerFrame, performancePolicy.maxPassesPerFrame)
```

| Quality preset | `maxPassesPerFrame` |
|----------------|---------------------|
| battery | 4 |
| balanced | 8 |
| ultra | 16 |
| auto (mobile) | 6 |
| auto (desktop) | 12 |

When over budget, excess dispatches are skipped and a console warning is logged.

## Encoder boundaries

All graph nodes run inside the slot's single `GPUCommandEncoder` for the frame. Each expanded dispatch opens one `beginComputePass` / `endComputePass` pair. The frame blit and end-of-frame `dataA`/`dataB` → `dataC` feedback copies run outside the graph, unchanged from Tier B.

## Registry build

```bash
node scripts/buildMultipassRegistry.js
```

Scans `shader_definitions/**/*.json` and regenerates [`src/renderer/multipassRegistry.ts`](../src/renderer/multipassRegistry.ts):

- `MULTIPASS_REGISTRY` — Tier B linear chains
- `GRAPH_REGISTRY` — Tier C graphs keyed by primary shader id
- `resolveGraphForShader(shaderId)` — graph lookup

Wired into `prestart` / `prebuild` alongside `generate_shader_lists.js`.

## Validation

`validateGraph(graph)` checks:

- Known texture roles only
- `repeat` ∈ [1, 64]
- Pass count ≤ `maxPassesPerFrame`
- Dependency order: no read of a role before it is produced (seed: `dataC` from previous frame)
- No cyclic dependencies within the expanded dispatch list

## Reference implementations

| Shader | Pattern |
|--------|---------|
| `wave-tank` | step×3 → inject → render (Jacobi-style wave sim) |
| `quantum-foam-pass1` | 3-node graph (field → particles → composite) |

## WASM follow-up

Graph execution is **TypeScript WebGPU only** in v1.

**Follow-up:** [GH #929](https://github.com/ford442/image_video_effects/issues/929) — port `GraphRunner` to `wasm_renderer/frame.cpp` (`dispatchSlot` equivalent) once TS path is proven. Track under Tier B WASM promotion ([`WASM_PROMOTION_TRACKING.md`](../WASM_PROMOTION_TRACKING.md)).
