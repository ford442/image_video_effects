# NOTES — Stellar / Topological Eight (2026-09-27)

Scope: 8 shaders (7 upgrades + 1 rescue). Out of scope, already carrying `Ideas:` (09-15): `gen-topological-acoustic-knots`, `gen-void-harmonic-cymatic-resonator`.
Real-GPU visual QA: **external** — nothing below was seen on a GPU.

| Shader | Kept verbatim | A packing | Ideas in the diff (tagged `// IDEA n:`) | Silent bugs fixed |
|---|---|---|---|---|
| gen-singularity-forge | 100-step single march, torus disk + fbm, jet SDF, swirl-advected HDR history, mouse lens, 4 params | raw HDR rgb + semantic alpha (ACES on `writeTexture` only) | 1 relativistic beaming + gravitational redshift (`diskBeam`); 2 log-spiral arms (`3θ + 9 ln r − ωt`) replacing 16 radial spokes; 3 precessing helical jet, knots ride the corkscrew | none found |
| gen-stellar-plasma-ouroboros | SDFs, `max(cylD,-hexD)`, path distort, 100 steps, OkLab/blackbody, Fresnel rim, mouse rd nudge, 4 params | display RGBA (ACES, exposure 0.8) | 1 peristaltic bolus (`bolusAt`) hinging hex plates outward; 2 seam light through hex gaps gated by bolus phase | now writes `dataTextureA`; ACES replaces `clamp(col,0,1)`; alpha coverage-based; depth from march distance (was `readDepthTexture` passthrough) |
| gen-stellar-web-loom | 80-step march, 3 fbm, mouse singularity + click deepen, starfield, streaks, HDR trails, ACES, 4 params | `A.rgb` HDR + `A.a` depth (documented, kept) | 1 plucked standing-wave threads (`pluck()`); 2 warp/weft hues + over/under thickness by cell parity; 3 gyro ring per node | `extraBuffer[133/134]` burst (never persists, racy) → stateless `clamp((bass−0.3)·5, 0, 2)` |
| gen-symbiotic-plasma-reef-matrix | terrain, `coralBranch`, smin, entity orbit/flee, palettes, 80 steps, camera, mouse, fog/ACES | display RGBA | 1 dock-and-pulse (entity near a branch axis flares it, pulse climbs base→tip); 2 caustic dapples by height | C read via sampler → `textureLoad`; alpha 1.0 → semantic; **Reef Density was dead** → branch count 3..9, exactly 5 at default |
| gen-tectonic-plasma-crucible | slab/fissure/magma SDF, blackbody magma colour, `heatHaze`, bubbles, camera, mouse stress, 100 steps | display RGBA | 1 continuous incandescent-crack ramp (`incandescent()`) + unlit thermal halo; 2 per-plate bobbing/tilt from true Voronoi cell hash + bass rift widening `fissureWidth` | C via sampler → `textureLoad`; alpha 1.0 → semantic; `pow(t−0.4, 2.0)` negative base → explicit square; persistence was mixed before ACES (double tone-map) → now after ACES |
| gen-topological-phase-weave | director/defect layout, iridescent map, mouse defect + pin, Euler tint, phase colour, C exact load, ACES, 4 params | display RGBA (ACES) | 1 true LIC (5 steps each way, analytic gradient, `licConvolve`); 2 ±½ defect glyphs (comet wedge / trefoil lobes); 3 order parameter drives coherence (`cohere`) | `extraBuffer[0]` "prevBass" (smoothing was a no-op + thread-(0,0) race) → stateless; no extraBuffer writes |
| gen-vortex-cathedral | arches/rings/columns/fog, two 20-step god-ray passes, sanctum glow, starburst, edge CA, premultiplied `writeTexture`, 4 params | display RGBA (ACES, non-premultiplied) | 1 arch-gated crepuscular shafts; 2 stained-glass sector tint (5-jewel table); 3 counter-rotating vault ring at r≈0.6 | `extraBuffer[0]` smoothing no-op → stateless, writes removed; C via sampler → `textureLoad`; **A packing lie** (A held masks, C read as colour) → display RGBA; `normalize(0)` in `godRays` guarded |
| gen-wasm-hls-physarum-swarm (RESCUE) | F/L/R sensing (`trail + food·2.5`), 4 slider roles/ranges, audio turn/speed/deposit, 150 px mouse pull, 3×3 blur, video-as-food, chromatic palette | raw sim state `(trail, mx, my, hue)`; ACES only on `writeTexture` | 1 peristaltic cytoplasm streaming along vein heading; 2 tube shading + foraging-front colour | agent state lived in `extraBuffer[0..]` (re-seeded identically every frame = static noise; clobbered audio/FFT slots) → Eulerian agents in A/C; mouse pull takes shortest arc; alpha = vein coverage |

## Look changes at saved values (tell the user)
- **physarum:** was static noise; now a live sim, so everything visible is new. Deposit is normalised by `(1−decay)/0.04125`, so Trail Decay changes persistence, not brightness. Audio turn clamped to 0.9 rad/step.
- **ouroboros:** ACES at exposure 0.8 (0.5→~0.54, 1.0→~0.75) replaces the hard clamp; brightness curve differs.
- **web-loom:** thread colour blends `tempTint` at 50% so the three axis hues stay distinct; the old single violet shifts.
- **tectonic:** persistence now mixed after ACES (fixes double tone-mapping), a small tonal change.
- **cathedral:** ghost tint changes slightly (C now holds true colour instead of arch/ring/centre-light masks).
- **reef:** default still exactly 5 branches; positions/seeds of branches 0–4 unchanged.

## Numpy gate for the physarum rescue (`physarum_sim.py`, N=128, 1500 steps; re-run by the coordinator, numbers reproduced)
Default: mean trail 0.184, mass ×1.34, trail variance 5.0e-4 → 2.9e-3 → 3.4e-3 (steps 25/300/1500), giant vein component 0.99, saturated fraction 0.
All 8 extremes: alive (mass ×1.02–1.78), not saturated, heading changes 0.75–1.06 rad/frame. **Weakest cases:** `Trail Decay = 1` (cv 0.16, variance 7e-4 → near-uniform trail, faint veins) and `Sensor Distance = 0` (giant component 0.66, 42 components). This is a port, not the WGSL; real-GPU confirmation is still needed.

## Open items for real-GPU QA
- singularity-forge beaming scale (`0.7·D³·g²`, clamped 3.0) untuned.
- Cost: phase-weave ≈1.4–1.6× HEAD per pixel (agent estimate, not measured); web-loom adds 3 `pluck()` calls per march step; cathedral +1 atan2/sin/smoothstep per god-ray step ×2 passes.
- ouroboros ACES exposure, cathedral vault ring vs sanctum visibility at default sliders, physarum vein look at saved sliders.

## Not touched / left as is
- web-loom description gained one sentence naming the new ideas (no schema change). Existing web-loom/singularity-forge feature tags kept.
- tectonic `slabHeight` still hashes the grid cell, not the Voronoi cell (idea 2 adds the true plate hash on top).
