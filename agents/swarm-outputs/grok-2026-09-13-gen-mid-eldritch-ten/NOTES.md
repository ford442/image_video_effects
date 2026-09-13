# Grok-2 mid-complexity generative ten — NOTES

Date: 2026-09-13. Cards in `BRIEFS.md`. Plumbing floor applied where already present; ideas are the upgrade.

Skipped (already idea-rich):
- `gen-electric-kaleidoscope-storm` (2026-09-09 Lichtenberg afterimage + leader/return-stroke)
- `gen-feedback-echo-chamber` (2026-09-11 harmonic echo ladder + standing-wave nodes; extraBuffer[133] kept)

## gen-eldritch-tesseract-hive-mind
- KEPT: rotation/swarm/tearing/iridescence; extraBuffer[133..134] burst; XZ+YW 4D tumble; voxel mat 2
- A PACKING: raw HDR trail RGB + raymarch depth in A.a; ACES on writeTexture only
- Ideas in diff: `p4hive` W-cell along unused W; `nPhero` radial pheromone lanes beside tangential streaks

## gen-emergent-calligraphic-ecosystems
- KEPT: stroke-density/ink-width/complexity/neon-mode; 3×3 glyphCluster; LV prey/predator; click ink
- A PACKING: ACES display RGBA
- Ideas in diff: `pressure` swell in `stroke`; `chase` offset along flow for flora seeds
- Floor: depth is ink coverage (was `vec4(0.0)`)

## gen-emergent-script-gardens
- KEPT: stroke-density/curvature/garden-scale/ink-neon; PHYLLOTAXIS; plantedSeed; A.a overgrowth
- A PACKING: pre-ACES color RGB + totalInk in A.a; ACES on writeTexture only
- Ideas in diff: opposing-family `orbit2` parastichy veins; `ligature` brush to +X neighbor

## gen-evolutionary-cellular-gardens
- KEPT: cell_scale/evolution_speed/invasive_force/bioluminescence; extraBuffer[133..138] spring; three CA layers
- A PACKING: trail RGB + colonyAge in A.a; ACES on writeTexture only
- Ideas in diff: `sporulate` where fine lives and coarse is dead; `rhizoid` filaments toward the spring well

## gen-fractal-bioluminescence-spore-network
- KEPT: sporeDensity/networkComplexity/bioluminescenceIntensity/audioReactivity; kaleido + Clifford pair
- A PACKING: ACES display RGBA
- Ideas in diff: `hypha` capsule between Clifford centers; `quorum` pulse from spore separation

## gen-fractal-chrono-dendrite-forge
- KEPT: dendriteComplexity/entropyPulseRate/spectralDispersion/gravityWellStrength; abs-fold cylinders; no extraBuffer
- A PACKING: ACES display RGBA
- Ideas in diff: `bud` perpendicular cylinder per iteration; `recalescence` flash on entropy-pulse crests

## gen-glass-mosaic-liquid-refraction
- KEPT: facet-density/bevel-width/refraction-strength/ripple-speed; voronoi + heightMap photo refraction
- A PACKING: ACES display RGBA
- Ideas in diff: `paneTilt` Snell per Voronoi cell; `meniscus` kick at the lead came
- Floor: clamped displaced UVs

## gen-gravitational-ferrofluid-singularity-engine
- KEPT: singularityMass/fluidViscosity/spikeDensity/iridescence; angular+radial fronts; 8 droplets; no extraBuffer
- A PACKING: ACES display RGBA
- Ideas in diff: `crest` Rosensweig ridges on angular×radial peaks; photon-ring `sheen` outside the horizon

## Floor
- Saved `params` / `updatedParams` byte-exact. Features gained `upgraded-rgba` only.
- No new springs. extraBuffer[133..134] (eldritch burst) and [133..138] (cellular attractor) kept.
- Gates: Naga 8/8, extraBuffer 0 new `[0..132]`, dead sliders 0, catalog 1,365 unique IDs / 470 generative, SKIP_WASM_BUILD=1 build green. Jest 6 fail = pre-existing WASM `bridge/api.js`, not this batch. Real-GPU visual QA: external.
