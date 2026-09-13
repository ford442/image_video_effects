# Grok-2 mid-complexity generative ten — NOTES

Date: 2026-09-13. Cards in `BRIEFS.md`. Plumbing floor applied where already present; ideas are the upgrade.

## gen-hyper-bismuth-clockwork
- KEPT: complexity/clock_speed/iridescence/grid_density; hopper+KIFS+gears; magnetic cursor; gearShock; ACES display A; no extraBuffer
- A PACKING: ACES display RGBA
- Ideas in diff: `sdBismuthStep` terrace ridge on boolean cuts; `mesh` flash at `gearPhase` crest

## gen-hyper-dimensional-bismuth-matrix
- KEPT: four params; extraBuffer[133] bass envelope; hopper+KIFS+stairs; crystalShock; ACES display A
- A PACKING: ACES display RGBA
- Ideas in diff: `twin` where hopper≈KIFS; `riser` film-thickness phase on stair floor index

## gen-hyper-dimensional-tesseract-labyrinth
- KEPT: complexity/edge_glow/warp_field/fly_speed; rotate4D XW+YZ; foldShock; fly camera
- A PACKING: ACES display RGBA
- Ideas in diff: mat 3.0 W-slice ghost frame from `q4.w`; `corridor` glow on cube midplanes

## gen-hyper-refractive-rain-matrix
- KEPT: rainDensity/dropSpeed/fluidViscosity/stormIntensity; capsule smin; raw HDR A
- A PACKING: raw HDR refractive rain display RGBA
- Ideas in diff: `d1Tail` streak capsule; primary bow at `dot(-rd,n)≈0.74`

## gen-hyperbolic-crystal-symbiosis
- KEPT: growthSpeed/competition/curvature/mutation; Poincaré tiling + crystalFacet; HDR A
- A PACKING: raw HDR crystal + trail RGBA
- Ideas in diff: horocycle rings on `cellDist`; species takeover mix at thin `facetBorder`

## gen-gravitational-strain
- KEPT: well-count/mass/bend/emission; RK4; Einstein rings; accretion; strain runners
- A PACKING: (depth, raySpeed, emEnergy, alpha) — not display
- Ideas in diff: `photonSphereGlow` at 1.5 Rs; star field sample displaced along `gravGrad`

## gen-gravito-phononic-accretion
- KEPT: mass-scale/body-count/lens-strength/gas-density; per-band bodies; mouse mass
- A PACKING: tone-mapped temporal display RGB
- Ideas in diff: orbital beaming crescent; phononic spiral on FBM density

## gen-graviton-plasma-lotus
- KEPT: four updatedParams; extraBuffer[133..138] spring; smin core+petals
- A PACKING: ACES display RGBA
- Ideas in diff: KIFS abs-plane veins; nectary corona where core≈petal SDF

## gen-galactic-aether-crystal-geode-core
- KEPT: crystal-density/core-glow/fractal-iterations/gas-density; cellular crack; KIFS
- A PACKING: ACES display RGBA
- Ideas in diff: druse sparkle on inner cavity; convection swirl on volumetric gas

## gen-glacial-aether-quantum-cavern
- KEPT: ice-density/plasma-glow/fracture-rate/cavern-scale; materials 0/1/2; frost/thin-film
- A PACKING: ACES display RGBA
- Ideas in diff: ablation scallops on ice walls; meltwater wet specular on `-n.y`

## Floor
- Saved `params` / `updatedParams` byte-exact. Features gained `upgraded-rgba` only.
- No new springs. extraBuffer[133] (matrix) and [133..138] (lotus) kept.
- Gates: Naga 10/10, extraBuffer 0 new `[0..132]`, dead sliders 0, catalog 1,365 unique IDs / 470 generative, SKIP_WASM_BUILD=1 build green. Jest 5 fail = pre-existing WASM bridge. Real-GPU visual QA: external.
