# Multipass Simulation Contract (13 bindings)

How to run physics sims **without** new bind groups or a graph runner.

---

## What exists today

### Frame feedback (automatic, usage-gated)

After each chained slot's full pass chain, `WebGPURenderLoop` copies data textures for the *next* frame. Since the usage-gating change, only the copies the frame actually needs are recorded (derived per shader at compile time by `analyzeShaderBindings()` in `src/renderer/ShaderCompilation.ts`):

- `dataTextureA` → `dataTextureC` — only when a shader in the slot's chain writes `dataTextureA`
- `dataTextureB` → `dataTextureC` — only when a shader in the slot's chain writes `dataTextureB`; it runs after the A copy, so if you write **both**, B wins — use **one** primary feedback channel per effect
- Both copies are skipped when no enabled shader reads `dataTextureC`

Just write your state and read `dataTextureC` — the gating is invisible to shader authors. The same applies to the history ring (binding 13): the per-frame history copy only happens when an enabled shader actually samples `historyTexture`.

See `src/renderer/webgpu/WebGPURenderLoop.ts` and `src/renderer/slotOrchestrator.ts`.

### Linear multipass (same frame)

`resolveMultipassChain()` runs passes **sequentially in one command encoder** with the **same** bind group. Note that `dataTextureA` / `dataTextureB` are bound **write-only** and `dataTextureC` refreshes only *after* the slot's whole chain — so pass *N+1* **cannot** read what pass *N* wrote this frame; cross-pass state travels through `dataTextureC` with one frame of latency.

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

**Ping-pong across frames (Tier B — no graph runner):**

```
Pass 1: read dataTextureC (t-1)  → write dataTextureA (integrate)
Pass 2: read dataTextureC (t-1)  → write dataTextureB (scratch — NOT readable by later passes)
Pass 3: read dataTextureC (t-1)  → write writeTexture + dataTextureA (render + commit)
End of slot: dataTextureA → dataTextureC (automatic — feeds next frame)
```

A and B are write-only within a frame; every pass reads the *previous frame's* committed state from `dataTextureC`. State written to A becomes visible in C on the next frame (one-frame latency). True same-frame pass-to-pass handoff needs the Tier C graph runner below.

---

## What the graph runner provides (Tier C — landed)

See [`docs/MULTIPASS_GRAPH.md`](../../docs/MULTIPASS_GRAPH.md) for the JSON schema and copy-barrier rules.

- **Intra-frame ping-pong loops** — e.g. Jacobi pressure ×40, cloth constraints ×5, without 40 separate WGSL files
- **Repeat counts** — `repeat: N` on graph nodes
- **Pass budgets** — `maxPassesPerFrame` + `performancePolicy` caps

Until WASM parity ([#929](https://github.com/ford442/image_video_effects/issues/929)): TS WebGPU path only.

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
