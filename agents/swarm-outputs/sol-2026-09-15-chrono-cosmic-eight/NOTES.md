# Chrono-Cosmic Mechanisms Eight — Implementation Notes

## `gen-chronos-crystal-labyrinth`

- Kept: folded octahedron maze, moving camera, dispersion/gravity/fold/glow control roles.
- Added: moving diagonal time-fault seams feed the SDF and local facet split; twelve hour-line caustics sweep hit facets.
- Floor: fake C-audio replaced with `plasmaBuffer[0].xyz`; top-down pointer mapping corrected; ACES display, semantic alpha, depth, and display A added.
- A packing: ACES display RGBA.

## `gen-aetherial-plasma-loom`

- Kept: four-octave 3D FBM, volumetric density integration, density/flow/twist/brightness roles, held-pointer twist.
- Added: opposing angular heddle lanes shape thickness; traveling shuttle phase necks the ribbon and accumulates warm knots.
- Floor: fake C-audio replaced with three-band plasma audio; pointer Y corrected; first-density depth, alpha, ACES, and display A added.
- A packing: ACES display RGBA.

## `gen-celestial-yggdrasil-matrix`

- Kept: KIFS tree, twisted trunk, branch/plasma/gravity/glow roles, gravity warp and camera orbit.
- Added: golden-angle branch buds at radial branch shells; paired cyan/gold sap pulses counterflow through the tree.
- Floor: removed generic post-color control shim; Branch Complexity now controls KIFS iterations; pointer spaces aligned; all audio bands live; A now matches ACES display.
- A packing: ACES display RGBA.

## `gen-chrono-kinetic-fractal-engine`

- Kept: 4D rotation, repeated torus/octahedron mechanism, orbit-trap iridescence, four saved control meanings.
- Added: angular torus teeth plus pallet-contact trap; alternating layer direction and elastic backlash phase.
- Floor: fake C-audio replaced with `plasmaBuffer`; invalid float modulo and dynamic array-index path repaired; final hit depth/alpha/ACES display made honest.
- A packing: ACES display RGBA.

## `gen-celestial-clockwork-plasma-loom`

- Kept: toothed astrolabe rings, plasma material, singularity core, four control roles, local mouse time dilation, exact-C display history.
- Added: radius-dependent Keplerian gear rates; opposed over-under plasma strands and traveling shuttle packet.
- Floor: all three audio bands drive distinct loom details; semantic current/history alpha retained; no new state buffers.
- A packing: ACES display RGBA with exact-C temporal blend.

## `gen-chronos-biomechanical-void-leviathan`

- Kept: capsule/ellipsoid creature, ribs, temporal KIFS wake, nebula, mouse orbit, four saved control meanings.
- Added: smoothly interpolated per-vertebra swim lag; twin auroral helices in the trailing wake.
- Floor: canonical Uniforms layout restored; `u.time` replaced by canonical time; ACES clamp, semantic alpha, depth, display A, and three-band audio added.
- A packing: ACES display RGBA.

## `gen-chronomorphic-glass-tesseract`

- Kept: six 4D rotation planes, hypercube distance, chronomorphic surface ripple, dispersion/IOR/gravity/fold roles, pointer lens polarity.
- Added: hidden-W face-crossing metric focuses cyan/gold caustic sheets; W-phase delays perturb RGB IOR for temporal birefringence.
- Floor: fake C-audio replaced with `plasmaBuffer`; safe pointer normalization; render result now carries alpha/depth; ACES display A added.
- A packing: ACES display RGBA.

## `gen-quantum-liquid-metal-chronosphere`

- Kept: simplex-displaced sphere, density/tension/flow/iridescence meanings, held-pointer gravity, thin-film/Fresnel material.
- Added: coupled low/high capillary modes; latitude-dependent rotating time bands in shape and material.
- Floor: zero-radius guard; correct ripple packing (`xy` origin, `z` start time, no fake `w` amplitude); three-band audio, ACES, semantic alpha, depth, and display A. Legacy `parameters` remains byte-structure exact; canonical `params` added with identical values.
- A packing: ACES display RGBA.

## Batch gates

- Naga + binding/workgroup gate: 8/8.
- New low-slot `extraBuffer` writes: 0.
- New dead sliders: 0/32.
- Saved `params` / legacy `parameters`: exact against `origin/main` for all eight.
- Catalog: 1,367 manifest/list parity; 1,380 unique definitions with 13 expected pass-only entries.
- Jest: 97/101 suites and 689/696 tests pass; only four pre-existing WASM `./bridge/api.js` resolver suites fail.
- `SKIP_WASM_BUILD=1 npm run build`: passes.
- Real-GPU visual QA: external; Cloud VM has no WebGPU adapter.
