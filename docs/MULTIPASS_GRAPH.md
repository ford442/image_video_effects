# Multipass Graph (Tier C)

Declarative **intra-frame** compute graphs for iterative sims (Jacobi, wave steps, cloth constraints).

Extends Tier B linear chains ([`multipassRegistry.ts`](../src/renderer/multipassRegistry.ts)) with same-frame texture handoff, loop counts, and pass budgets.

**Related:**
- Bind group layout: [`docs/BINDING_CONTRACT.md`](BINDING_CONTRACT.md)
- Sim texture packing: [`agents/swarm-tasks/advanced-physics/MULTIPASS_SIM_CONTRACT.md`](../agents/swarm-tasks/advanced-physics/MULTIPASS_SIM_CONTRACT.md)
- Builder: [`scripts/buildMultipassRegistry.js`](../scripts/buildMultipassRegistry.js)
- Validator: [`src/renderer/multipassGraph.ts`](../src/renderer/multipassGraph.ts)
- Authoring workspace: [`docs/GRAPH_LAB.md`](GRAPH_LAB.md) (experimental, `?graphlab`)
- Frame plan + executor: [`src/renderer/webgpu/framePlan.ts`](../src/renderer/webgpu/framePlan.ts) (graph nodes and linear slots compile into one op list; `GraphRunner.runGraph` is the stand-alone shim)

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
| `dispatch` | no | `pixels` (default) or `simState` (sim-ring agents; see [`BINDING_CONTRACT.md`](BINDING_CONTRACT.md)) |
| `scalable` | no | Opt in to per-node resolution scaling (see below) |
| `minScale` | no | Lowest scale adaptive demotion may pick: `0.25`, `0.5` (default) or `0.75` |

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

When over budget, iterative `repeat` counts shrink first and the last node that writes `color` is kept. Excess work is reported as truncated steps (Dev Tools + `GraphRunReport`), with a console warning (once per graph and cap).

### Frame budget (#1314)

On top of the per-graph cap, the TS renderer applies one budget to the whole frame:

```
framePassBudget = performancePolicy.maxPassesPerFrame × performancePolicy.maxActiveSlots
```

That is 4 for battery, 16 for balanced and 48 for ultra. Linear (Tier A/B) passes are charged first, because truncating a chain would change the picture. Graphs then share what is left in encode order. Each graph still stays within `effectiveCap` and keeps at least its color writer. A stack made only of graphs gets exactly what the per-graph caps gave it before. The C++ mirror ([`performance_policy.h`](../wasm_renderer/performance_policy.h)) is unchanged, since the frame plan is TS-only while WASM is frozen.

## Per-node resolution scale (opt-in, #1314)

A node may declare `"scalable": true` (plus an optional `"minScale"` of `0.25`, `0.5` or `0.75`; the default is `0.5`). Adaptive performance can then run that one node below the working size instead of shrinking the whole canvas. The renderer wraps the dispatch in a scaled island:

1. `readTex` and `dataTexC` (the readable bindings 1 and 9) are bilinearly resampled into scratch textures at the scaled size. `u.config.zw` is patched to that size.
2. The node dispatches over the scaled size, using a bind group over the scratch set. Depth and history stay full size.
3. Each **declared** write (`color`, `dataA`, `dataB`) is resampled back to full size, and `config.zw` is restored.

The shader needs no changes as long as it derives coordinates from `u.config.zw` or `textureDimensions`. Only opt in nodes whose output tolerates resampling (orientation or flow fields, blurs, tensors), not per-pixel simulations. Scratch for all scale levels is capped at 128 MiB; beyond that the node runs at full size.

The policy lives in `nodeScaleAdvisor.ts`. When FPS is below target and the profiler shows one scalable node taking more than 35 % of compute GPU time, that node steps down by 0.25 (2 s cooldown). Otherwise the global scale steps as before. On recovery, nodes are promoted before the canvas. Debug or test overrides go through `__pixelocity__.setNodeScale(slot, nodeId, scale)`; diagnostics report `webgpu.nodeScales`.

Example: `anisotropic-kuwahara`'s `tensor` node (structure-tensor field, `minScale` 0.5).

## Encoder boundaries

All graph nodes run inside the frame's single `GPUCommandEncoder` (one `queue.submit` per frame, #1314). They are compiled into the frame plan next to linear slots and bind the renderer's cached compute bind group, so no group is created per dispatch. Each expanded dispatch opens one `beginComputePass` / `endComputePass` pair. The frame blit and end-of-frame `dataA`/`dataB` → `dataC` feedback copies run outside the graph, unchanged from Tier B.

## Registry build

```bash
node scripts/buildMultipassRegistry.js
```

Scans `shader_definitions/**/*.json` and regenerates [`src/renderer/multipassRegistry.ts`](../src/renderer/multipassRegistry.ts):

- `MULTIPASS_REGISTRY` — Tier B linear chains
- `GRAPH_REGISTRY` — Tier C graphs keyed by primary shader id
- `resolveGraphForShader(shaderId)` — graph lookup (a [runtime graph](#runtime-graphs) for the id wins)

Wired into `prestart` / `prebuild` alongside `generate_shader_lists.js`. The work is `buildRegistry({ defsDir, outFile, write })`, exported for tests.

Writing these definitions by hand is optional: the [Graph Lab](GRAPH_LAB.md) authors, validates, runs and exports them.

## Validation

`validateGraph(graph)` returns the error strings the frame planner acts on; an invalid graph is reported (`GraphRunReport.errors`) and not encoded. It checks:

- Known roles only; `simIndex` and `simHash` are never write targets
- `repeat` ∈ [1, 64]
- Pass count ≤ `maxPassesPerFrame`
- Every node has an `entry`, and declares reads or writes
- `minScale` is one of `0.25, 0.5, 0.75, 1`; `simState` dispatches are not `scalable`
- Dependency order, simulated over the expanded dispatch list: no read of `dataA` / `dataB` before something in the frame produced it (`dataC` is seeded from the previous frame)
- `knownEntries` (optional): every `entry` is one of the given WGSL ids

`diagnoseGraph(graph, { knownEntries })` is the same pass with structure, for tools. Each diagnostic has a stable `code`, a `severity`, the same message `validateGraph` returns, and `nodeId` / `iteration` / `role` where they apply. Error codes: `max-passes`, `empty-graph`, `pass-budget`, `node-id`, `missing-entry`, `repeat-range`, `invalid-role`, `sim-index-write`, `sim-hash-write`, `invalid-dispatch`, `no-io`, `min-scale`, `scalable-sim`, `dependency`, `cycle`.

Nodes run in array order, so a graph cannot contain a cycle in the graph-theory sense. `cycle` is the diagnostic for an unsatisfiable read that is circular: the node waits on a role only it writes, or on a later producer that in turn needs something this node writes. Any other unsatisfiable read is `dependency`.

`diagnoseGraph` also returns **warnings**, which never change what the planner does: `no-color-writer` (nothing reaches the display), `duplicate-node-id` (per-node scale overrides and pass timings key on the node id), `non-integer-repeat`, `ineffective-role` (reading `color`, writing `read` or `dataC`), `unbounded-max-passes` (above 64; presets cap a graph at 4–16).

## Runtime graphs

`runtimeGraphs.ts` is an overlay on the generated registry: `setRuntimeGraph(id, graph | null, simRing?)` makes `resolveGraphForShader`, `hasGraph` and `getGraphEntryIds` answer for an id that is not in `shader_definitions/`. The [Graph Lab](GRAPH_LAB.md) runs its draft this way (id `graphlab-draft`), so the draft goes through the same planner, pass budgets, truncation and color-writer rules as a shipped graph.

- One overlay per JS realm. The render worker has its own copy, fed by the `setRuntimeGraph` render command; `RendererManager.setRuntimeGraph` sets both.
- Pass a **new graph object** for every change. Validation, expansion and pass caps are memoised per graph object, so mutating a registered graph in place keeps serving the old plan.
- A runtime graph wins over a static one with the same id; `null` restores the static graph.
- TS WebGPU only.
- The optional `simRing` (`{ stateCount }`, the definition field as consumed) is what `resolveSimRingRequest` returns for the graph's id and its entries while it is registered; it wins over `SIM_RING_REGISTRY`. It only sizes the ring: the ring is still armed by `WebGPURenderer.loadShader` → `SimRing.ensure` when an entry that declares `@group(1)` compiles, and group 1 is still bound only to those entries. A request that is set after the entries compiled takes effect on their next compile.

## Sim roles and the spatial hash

With the [sim ring](BINDING_CONTRACT.md#sim-ring-opt-in-group1-ts-renderer-only) on, nodes may read and write `simState` and read `simIndex`, and dispatch over `simState` (`"dispatch": "simState"`). A fourth role, `simHash`, is **read-only** and opt-in per definition (`"simRing": { "stateCount": N, "spatialHash": true }`).

- A node lists `simHash` in `reads`; the planner does the rest. Immediately before the first dispatch that reads a stale hash, `expandGraph` inserts one planner-owned dispatch (`entry: "__simHashBuild"`, `dispatch: "simHashBuild"`): reset the heads, scatter every agent. A `simState` write makes the hash stale again, so a second reader after a write gets a second build; readers with no write between share one.
- **It is a pass.** `countGraphPasses`, `pass-budget` validation, `GraphRunReport.requested / executed / truncated`, the per-graph quality cap and the frame pass budget all include it. `murmuration` is 3 passes (scatter, flock, render) and `photon-bins` 4 (march, scatter, splat, present).
- **Truncation:** `shrinkGraphToCap` counts the build with the nodes, so dropping the last reader drops its scatter with it, and the colour write is dropped last: under a cap of 2, `murmuration` keeps only `murmuration-render`, never the render without its colour write.
- A graph that never reads `simHash` (DLA) gets no build and no change to its bind-group layout. A definition that sets `spatialHash` and no node reads the role, or a node reads it without the flag, is a `verify:device-policy` error.
- Pixel nodes that read the hash must not be `scalable`: agent positions and cells are in full working-size pixels.

### Authoring checklist

1. Entry declares `@group(1) @binding(3) var<storage, read_write> simHash: array<atomic<u32>>` (and whatever of bindings 0–2 it uses), `#include "_sim_hash.wgsl"` after `_prelude.wgsl`.
2. The node lists `simHash` (and `simIndex` if it reads neighbour positions) in `reads`; the graph needs a `simState` writer before it.
3. Park dead agents at `xy < 0`; walk chains with a visit cap of 8–16; read neighbour positions from `simIndex`, not `simState`.
4. The definition sets `simRing.spatialHash: true`. Under `?renderer=wasm` the first entry is refused (logged skip, no `LoadShader`).

## Reference implementations

| Shader | Pattern |
|--------|---------|
| `ripple-tank` | step×4 → inject → optics gather → render (flagship Tier C physics demo) |
| `fabric-of-reality` | verlet → constraint×4 → tear → render (cloth sim) |
| `photonic-caustics-graph` | emit → trace×2 → accumulate (caustic transport) |
| `murmuration` | scatter → flock (simState, reads simHash + simIndex) → render (65k agents, hashed neighbour steering) |
| `photon-bins` | march (simState) → scatter → splat (reads simHash + simIndex) → present (the agent form of `photonic-caustics-graph`) |
| `chromatographic-fluid` | force → advect → diffuse×2 → interact → phase → render (shared wind, RGB viscosity) |
| `gray-scott-tank` | gs-step×4 → inject → render (true Jacobi Gray–Scott) |
| `wave-tank` | step×3 → inject → render (minimal graph reference / tests) |
| `quantum-foam-pass1` | 3-node graph (field → particles → composite) |

`optical-flow-dream` moved to the canonical single-pass 13-binding path in
August 2026. It now estimates temporal flow from exact `dataTextureC` history
and no longer consumes the graph runner or binding 13.

## WASM follow-up

Graph execution is **TypeScript WebGPU only** in v1.

**Follow-up:** [GH #929](https://github.com/ford442/image_video_effects/issues/929) — port `GraphRunner` to `wasm_renderer/frame.cpp` (`dispatchSlot` equivalent) once TS path is proven. Track under Tier B WASM promotion ([`WASM_PROMOTION_TRACKING.md`](./WASM_PROMOTION_TRACKING.md)).
