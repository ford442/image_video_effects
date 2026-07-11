# Multipass Simulation Contract (13 bindings)

How to run physics sims **without** new bind groups or a graph runner.

---

## What exists today

### Frame feedback (automatic)

After each chained slot dispatch, `WebGPURenderer` copies:

- `dataTextureA` → `dataTextureC`
- `dataTextureB` → `dataTextureC` (second copy overwrites — use **one** primary feedback channel per effect)

See `src/renderer/WebGPURenderer.ts` (~1560) and `src/renderer/slotOrchestrator.ts`.

### Linear multipass (same frame)

`resolveMultipassChain()` runs passes **sequentially in one command encoder** with the **same** bind group. Pass *N+1* can sample what pass *N* wrote to `dataTextureA` / `dataTextureB` in the same frame.

Registry: `node scripts/buildMultipassRegistry.js` → `src/renderer/multipassRegistry.ts`

JSON shape (primary catalog entry only):

```json
"multipass": {
  "pass": 1,
  "totalPasses": 3,
  "nextShader": "ripple-tank-pass2",
  "passes": [
    { "pass": 1, "name": "Wave step", "file": "ripple-tank-pass1.wgsl" },
    { "pass": 2, "name": "Inject sources", "file": "ripple-tank-pass2.wgsl" },
    { "pass": 3, "name": "Render", "file": "ripple-tank-pass3.wgsl" }
  ]
}
```

Secondary pass WGSL files use `_` prefix or `-passN` suffix — **no** separate JSON. See `docs/SHADER_TEMPLATES.md`.

---

## Texture roles (simulation)

| Binding | Typical sim role | Access pattern |
|---------|------------------|----------------|
| `readTexture` (1) | Source image / initial condition | sample |
| `writeTexture` (2) | Final displayed color | store (last pass only) |
| `dataTextureA` (7) | **Write** sim state (current / next) | store |
| `dataTextureB` (8) | **Write** scratch / alternate buffer | store |
| `dataTextureC` (9) | **Read** previous frame state | sample (`non_filtering_sampler`) |
| `extraBuffer` (10) | Particle indices, broken springs, RNG seeds | storage |
| `plasmaBuffer` (12) | Audio bands | read |

**Ping-pong within one frame (Tier B — no graph runner):**

```
Pass 1: read dataTextureC (t-1)  → write dataTextureA (integrate)
Pass 2: read dataTextureA        → write dataTextureB (inject forces)
Pass 3: read dataTextureB        → write writeTexture + dataTextureA (render + commit)
End of frame: dataTextureA → dataTextureC (automatic)
```

Three logical buffers (prev / work / next) map onto A + B + C across time.

---

## What the graph runner will add (Tier C — blocked)

Do **not** implement these until #929 lands:

- **Intra-frame ping-pong loops** — e.g. Jacobi pressure ×40, cloth constraints ×5, without 40 separate WGSL files
- **Conditional branching** — skip passes when `zoom_params.w` = quality preset
- **Fan-out / merge** — photon emit ∥ trace with reduction
- **Cross-slot sim handoff** — slot 0 sim state → slot 1 render

Until then: cap iterations at ≤4 passes per chain or unroll modest loops inside one kernel.

---

## Reference implementations

| Shader | Passes | Pattern |
|--------|--------|---------|
| `quantum-foam-pass{1,2,3}` | 3 | field → particles → composite |
| `sim-fluid-feedback-field-pass{1,2,3}` | 3 | velocity → density → composite |
| `rd-on-video-pass{1,2,3}` | 3 | RD step → modulate → blend |
| `wave-equation` | 1 (legacy) | single-pass step+inject+render — upgrade target for agent 1 |

---

## Packing cheat sheet

Document packing in the WGSL header comment block.

### Wave tank (`ripple-tank` / `wave-equation`)

```
dataTextureA / C:  .r = height u,  .g = velocity ∂u/∂t,  .b = prev height,  .a = phase/driver
```

### Cloth (`fabric-of-reality`)

```
dataTextureA:  .rg = position xy,  .ba = prev position xy  (Verlet)
dataTextureB:  .r = strain highlight,  .g = tear mask,  .b = weave phase,  .a = debris age
dataTextureC:  read previous positions
extraBuffer:   broken spring bitfield (u32 pairs) — optional
```

### Caustics (`photonic-caustics`)

```
dataTextureA:  .rgb = accumulated irradiance (HDR),  .a = sample count / temporal blend
dataTextureB:  photon scratch (direction.xyz, wavelength in .w) — single-pass only
dataTextureC:  read previous accumulation
```

---

## Anti-patterns

| ⛔ Don't | ✅ Do |
|---------|------|
| Add binding 13+ | Pack into RGBA channels |
| `textureLoad` on `dataTextureC` in pass 1 after you wrote A in same pass expecting C updated | Read C at pass start; write A; pass 2 reads A |
| Separate JSON per `-pass2` file | One catalog id; `multipass.passes[]` lists files |
| `atomicAdd` without device feature check | Hierarchical reduce or luminance stamp (see phase-c agent 5c) |
| 15KB monolithic sim + render | Split step / inject / render |
