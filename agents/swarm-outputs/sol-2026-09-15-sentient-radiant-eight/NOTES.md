# Notes — Sentient / Radiant cosmic entities eight (2026-09-15)

Coordinator: Flash. Branch: `cursor/sentient-radiant-eight-720b`.

## Ideas landed (findable in WGSL)

1. **gen-sentient-aether-plasma-nebula-moth** — `g_vein` / `sin(wp.x)*sin(wp.z)` ridges on the FBM wing; trailing-edge `hash33` scale-dust on `-wp.z`.
2. **gen-sentient-bismuth-hypercrystal** — hopper `fract(q.y * 8)` treads after the Menger cuboid; stair-riser `palette` mix on `g_hopper`.
3. **gen-sentient-cyber-aurora-void-owl** — `abs(sin(q.x * 28))` barb grooves on lattice cubes; concentric `fract(ir * 14)` iris rings on `g_eye_off`. Head-look now rotates `xz` then `yz` without overwriting `headPos.x`.
4. **gen-sentient-quantum-chrono-leviathan-moth** — `pow(1 - voronoi, 3)` raised veins; two `sdCapsule` antennae from the head.
5. **gen-radiant-chrono-glass-nautilus** — septa at `fract(spiral_a * 1.5 + 0.5)` seams; nacre keyed to `floor(spiral_hit * 1.5)`.
6. **gen-radiant-cyber-chrono-void-stag** — pearl spheres on antler segments; `fract` gait pulses on hoof trails. Dead `ripples[i].w` glow loop removed (padding, always 0).
7. **gen-radiant-quantum-crystalline-forge** — recalescence on `abs(g_fold)` crests; hopper terraces on folded `p.y`. **Deleted** `applyGenerativePrimaryControls` (it stole Density/Chroma/Fog/Mouse Influence). Mouse Influence now scales the UV gravity well. ACES on display RGBA + A.
8. **gen-radiant-quantum-plasma-kraken-core** — sucker discs along each tentacle; chromatophore `sin(t + p)` flashes. Raw `zoom_params` (no 0–1 re-clamp).

## Floor

- `plasmaBuffer[0].xyz` bass/mids/treble. Removed fake C (`bismuth`) and `u.config.y` audio (owl, leviathan-moth, stag, kraken).
- Mouse: `vec2(zoom_config.y, 1 - zoom_config.z)` UV, y=0 bottom. Owl no longer divides by resolution. Stag no longer divides by `config.zw`. Forge no longer treats mouse as pixel coords.
- ACES display RGB; semantic alpha; hit-distance depth; `dataTextureA` = display RGBA. No B writes. No new springs. No extraBuffer.

## Params

- Existing `updatedParams` / bismuth `params` values byte-exact vs `origin/main`.
- Canonical `params` added where missing; bismuth gained additive `updatedParams`.

## Gates (Cloud VM, no GPU)

- Naga 8/8 (`wgsl_precommit_gate.py --files …`).
- extraBuffer new writes `[0..132]`: 0.
- dead sliders: 0 / 32.
- Catalog 1,367. `SKIP_WASM_BUILD=1 npm run build` green.
- Jest 689 pass / 6 fail = pre-existing WASM `./bridge/api.js` (4 suites).

Real-GPU visual QA is external.
