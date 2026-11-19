# Notes — attractor / field ten (2026-11-19)

Idea Cards were written first in `BRIEFS.md`. Saved `params` were not renamed or re-defaulted. ACES stays on the display path. Raw fields are not tone-mapped.

Formula used once: deep-water dispersion (§12.2D) on `ripple-bloom` only. No other §12.2 row is new in this batch. No shared spring, shockwave, or IQ palette was added.

Six pasted headers were migrated to `#include "_prelude.wgsl"` (`gen-lorenz-attractor`, `phosphorescent-jellyfish`, `voronoi-dynamics`, `dla-crystals`, `gen-lenia-2`, `quantum-ripples`). That migration is not the upgrade.

Three other files already edited on this branch (`deep-sea-thermal-vent`, `gen-quantum-fluorescent-nebula-anemone`, `gen-showcase-nebula-core`) still pasted the binding header, which made `pending` grow against `origin/main`. They were migrated header-only and recorded as hygiene. Their `Upgraded:` dates were not bumped.

## gen-lorenz-attractor

- Kept: `lorenz_step`, Monte Carlo splat, wing channels, speed weight, hero capsule chain, treble fold, sigma / rho / glow / decay.
- Added: lobe-switch bridge deposited into both wing channels; dark eyes at C±; cool highlight from the hero polyline's turning angle (`heroBend`).
- A packing: raw sim (right density, left density, speed density, display alpha). Unchanged meaning. ACES on `writeTexture` only.

## phosphorescent-jellyfish

- Kept: `sdBell`, `tentacleGlow`, swarm / size / trail / glow, per-band pulse, click dart, HDR trail.
- Added: contraction velum on the lower margin; manubrium under the bell.
- Feedback reads C with `textureLoad` (pixel chroma offset). A packing: HDR RGB + alpha. ACES on display only.
- JSON: `upgraded-rgba` added. Params untouched.

## ripple-bloom

- Kept: three-band Huygens loop, the four sliders, crest chroma, bloom, and the cinema passes already in the file.
- Added: §12.2D phase speed inside that loop; crest steepening from C.g; capillary ripple gated by the crest.
- A packing: raw wave `(ripple, height, bloomAmount, alpha)`. Previously written and unread. Now read back. ACES on display only.

## gen-dmt-fractal-zoom

- Kept: hybrid escape loop, smooth color, orbit trap, interior nucleus, argument spokes, zoom and click warp.
- Added: main-cardioid and period-2 bulb contours while zoomed out; equipotential rings from `log2|z|` in the exterior.
- A packing: ACES display RGBA. Unchanged.

## voronoi-dynamics

- Kept: site / mouse / click search, edge from second-minus-nearest, repulsion bubble, attraction ooze, four slider roles.
- Added: third-nearest Plateau nodes; edge hue rotated by the shared-border angle.
- A packing: `(centroidPos, nearestDist, nearestIdx)`. Unchanged. ACES on display only.

## dla-crystals

- Kept: freeze map, ripple and mouse seeds, stickiness as the probability, A = `(frozen, age, hue, branchId)`.
- Added: tip vs fjord stick and tip glow; branch-angle facet bias; walker speed sets the search reach and attraction strength scales the stick gate and the approach glow. Both of those sliders were previously unread. Audio is `plasmaBuffer[0]`, not `zoom_config.x`. C is `textureLoad`.
- A packing: raw sim. ACES on display only.
- Catalog note: definition `dla-crystals` points at the multipass graph (`dla-walkers` → `dla-render`). This file is the 257-line single-pass shader the batch named. The graph was not retargeted, and the upgrade ledger hashes the graph, so `dla-crystals` did not get an `upgraded` ledger row. The JSON features were left on the graph.

## gen-chaos-game-ifs

- Kept: three-map `ifsPoint`, occupancy tint, radial hole, settle weight, scaffold, glints, contraction echo, raymarched crystal, existing pointer spring.
- Added: darkening of the midpoint triangle (first excision); corner lock when successive iterates pick the same vertex.
- A packing: ACES display RGBA. Unchanged.

## gen-lenia-2

- Kept: 8-tap kernels, bell growth, predator-prey matrix, membranes, gel relief, Beer-Lambert, four slider roles, raw four-mass A.
- Added: cytoplasm where G(U) peaks inside a body; furrows where the interaction term is negative.
- A packing: raw four-species masses. Unchanged. ACES on display only.

## quantum-ripples

- Kept: `waveField`, opposite-phase twins, click stack, curl, Voronoi, portal SDF, four slider roles.
- Added: dark nodes where the twins cancel and bright antinodes where they align; R/B split along the displacement tangent.
- A packing: ACES display RGBA. Unchanged.
- JSON: `upgraded-rgba` added. Params untouched.
- Swizzle writes on `color.r` / `color.b` were rebuilt as a `vec3` so the display path stays valid WGSL.

## gen-wasm-hls-physarum-swarm

- Kept: semi-Lagrangian gather, Jacobian pile-up, three-sensor steer, mouse attraction, deposit/decay roles, raw `(trail, mx, my, hue)`. No extraBuffer.
- Added: refractory cut on the deposit of an abandoned tube; food exhaust desaturating the photo under the spent sheath; sensor-angle slider flattening the tube normal (wider fan, wider vein).
- A packing: raw sim. ACES on display only.

## Gates

Structural only. No GPU, so no visual QA.

- Naga 10/10 on the batch, plus the three hygiene migrations.
- `npm run verify:shaders:fix`: 11/11.
- Dead sliders: 0 new. extraBuffer: 0 new.
- `npm run build` succeeded.
- Vitest full run: 1930 passed, 14 failed, 1 skipped. Failures were 5s timeouts and two timing flakes while the numpy physarum and sph_fluid cases held the machine (those two hit their 240s cap and were not re-run). Isolated `shaderDefinitionSchema` re-run: 10/10. The schema test's full-catalog loop is what timed out under load.
- `dla-crystals` ledger: not an upgraded row, because the catalog hash is the multipass graph.
