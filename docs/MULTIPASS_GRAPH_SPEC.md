# Multipass Graph Spec (Tier C)

Extends Tier B linear chains ([`multipassRegistry.ts`](../src/renderer/multipassRegistry.ts)) with **intra-frame** texture handoff.

## Node types

| Type | Purpose |
|------|---------|
| `pass` | Single compute dispatch; explicit read/write texture roles |
| `pingPong` | Iterate shader N times alternating dataA ↔ dataB |
| `loop` | Repeat a subgraph N times |

## Texture roles

Same as [`MULTIPASS_SIM_CONTRACT.md`](../swarm-tasks/advanced-physics/MULTIPASS_SIM_CONTRACT.md):

- `read` — slot read texture (previous frame / input)
- `write` — final color output
- `dataA`, `dataB` — write-only scratch (same-frame handoff via GraphRunner rebind)
- `dataC` — previous-frame simulation state

## Implementation

- Builder/validator: [`src/renderer/multipassGraph.ts`](../src/renderer/multipassGraph.ts)
- Executor: [`src/renderer/GraphRunner.ts`](../src/renderer/GraphRunner.ts)
- Demo graph: `createRippleTankGraph()` — 3-pass ripple tank with same-frame A→B→write handoff

## Tier gates

| Tier | Capability |
|------|------------|
| A | Single-pass shaders |
| B | Linear multipass (`resolveMultipassChain`) — one-frame latency between passes |
| C | Graph runner — same-frame ping-pong, loops, fan-out (Jacobi×N, cloth) |

## Encoder boundaries

Each `pass` / `pingPong` iteration uses one compute pass inside the caller's `GPUCommandEncoder`. The host must call `createBindGroupForPass(readTex, writeTex)` to rebind bindings 1 and 2 per pass.
