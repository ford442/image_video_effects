# Densest Multi-System Seven — notes (2026-09-27)

Request listed 10 IDs. Out of scope because they already carry `Ideas:` lines: gen-sentient-quantum-chrono-leviathan-moth (09-15),
gen-symbiotic-chrono-mycelium-engine (09-13), gen-stellar-acoustic-resonance-manifold (09-15).

## Per shader

### gen-resonant-quantum-obsidian-scarab-engine
- Ideas: elytra plate seams lit by an outgoing core-breath pulse; plasma mirror (12-step reflected march vs core torus) in the obsidian; core corona gathered along the primary ray.
- Kept: map(), 100-step march, Lambert+pow32 core, held-mouse dust, 5% C feedback, fake CA, ACES×1.2, lum alpha, depth t/20, slider roles.
- A packing: ACES display RGBA (unchanged).
- Noted, not fixed: KIFS "rotation" is a shear (x overwritten before y) — it is the shape; seams replay it.

### gen-resonant-quantum-plasma-dragon-eye
- Ideas: fibre stroma + metallic flecks (Iris Complexity = fibre count); breathing slit with fibres anchored slit→ring; cornea sheen/catchlight/parallax; eyeshine + gaze shaft through the existing plasma haze.
- Bugs fixed: iris ring/pupil were infinite along the eye axis (glowing bar on side views); illegal extraBuffer[0] write; inexact C read; 2 negative-base pow; hardcoded alpha 1.0; dead Pupil Sharpness slider (now slit-tip sharpness, reproduces HEAD ellipse at default to ~1e-7).
- A packing: ACES display RGBA.

### gen-sentient-ferro-silicate-swarm
- Ideas: world-scale silicate assembly breath (brutalist SDF sampled at cell centre, locked cells snap to lattice); quartz facet crystallization; Si–O bond struts (Cohesion = thickness); curl-advected wake in the C smear.
- Bugs fixed: dataTextureA never written → C zero → effect rendered at ~25% brightness (DEFAULT LOOK BRIGHTER NOW); illegal extraBuffer[0] write/race; mouse pull was a uniform bias on every cell (now local); depth was 0.
- A packing: ACES display RGBA, alpha = occupancy; C read as display RGB.

### gen-sonoluminescent-chrono-geode-matrix
- Ideas: shock-front crystal ignition (jolt in map + hot band); collapse-deposited agate strata; flash translucency through thin shard walls (5-sample SDF probe).
- Bugs fixed: extraBuffer[133..135] "bass-transient kick" never persisted (zeroed each frame) and raced across tiles → stateless `min(2.5*bass, 2)`; header/JSON no longer claim transient detection (feature tag `bass-transient-kick` → `bass-kick`).
- A packing: raw HDR history (≤5) + semantic alpha, unchanged.

### gen-spectral-ferrofluid
- Ideas: Archimedean flux spirals from all 4 poles across the iso-|B| bands; Cotton-Mouton birefringence (Michel-Lévy tint + isogyre crosses from fieldDir); pole meniscus mounds with analytic specular normals.
- Bugs fixed: rms read plasmaBuffer[0].w (always 0) → mean of xyz; ripple loop could index past ripples[50].
- A packing: raw fields (fMag*0.25, fieldDir.xy, alpha), unchanged.

### gen-superfluid-quantum-foam
- Ideas: coalescing bubble necks (8-neighbour smin); film-drainage black-film pop with burst shells; Kelvin-wave vortex filament (Vortex Radius drives it, 0 = off).
- Bugs fixed: curlNoise differenced a raw hash (warps up to 6 units, shattered bubbles — DEFAULT LOOK CHANGES); floor/round mismatch split each bubble into 8 eighths; camera-inside-bubble blank frame.
- Left: inert extraBuffer[133..138] spring (never persisted; HEAD behaviour).
- A packing: ACES display RGBA premultiplied, unchanged.

### gen-symbiotic-bismuth-crystal-dragon-core
- Ideas: ichor seep on the crystal/sinew smin seam; peristaltic lub-dub boluses down the artery (Breathing Speed paced); warm core light on artery-facing facets + heat haze.
- Bugs fixed: camera sat inside the infinite sinew cylinder → every ray hit at step 0 → flat gold wash, labyrinth never visible (artery now capped at z=-2.5, 0.6 channel) — DEFAULT LOOK CHANGES A LOT; audio from extraBuffer[0] → plasmaBuffer[0].x.
- Floor added (header, ACES, semantic alpha, depth, A write). JSON: `parameters` unchanged; added updatedParams (mirrors parameters), features, workgroup_size, supportsDepth, updated (all existing schema keys).
- Refused: hopper/oxide/twin/flux ideas (catalog-saturated in bismuth siblings).

## Gates (coordinator re-run)
- naga 7/7, wgsl_precommit_gate 7/7, audit:extrabuffer PASS, dead-slider audit 0 new (agents).
- generate_shader_lists + check_duplicates: 1386 unique IDs, no dups.
- Jest: 741 pass / 6 fail — the 6 known pre-existing suites (bridge `./x.js` imports), not regressions.
- `SKIP_WASM_BUILD=1 npm run build`: Compiled successfully.
- Real-GPU visual QA: external. Not verified.
