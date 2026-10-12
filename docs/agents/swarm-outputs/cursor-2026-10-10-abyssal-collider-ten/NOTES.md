# Batch Notes — abyssal-collider-ten

All target shaders in this batch now use `#include "_prelude.wgsl"` (10 migrated).  
Saved `params` were preserved for all 10 matching definitions.

## Per-shader upgrade notes

- `gen-abyssal-plasma-void-medusa`
  - Kept verbatim: lantern-root medusa body plan, shell translucency and void-current identity.
  - Added: nematocyst strobe ringlets (`rootBand`/`rootPulse`), bell-rim ciliary sparkles (`rimBand`/`cilia`).
  - A packing: raw HDR linear RGB + semantic alpha (unchanged).

- `gen-abyssal-quantum-leviathan-skeleton`
  - Kept verbatim: whip-wave spine motion, marrow canal + strain glow, bow-wave current parting.
  - Added: vertebral electroplate ladders (`vertebra`), caudal vortex-bead shedding (`bead` in volumetrics).
  - A packing: raw HDR history RGB + semantic alpha (unchanged).

- `gen-astral-plasma-accretion-forge`
  - Kept verbatim: dust-lane absorption, Keplerian shear lanes, gravitational redshift model.
  - Added: Rossby-vortex eye knots (`rossby`), polar reconnection flare knots (`pole`/`recon`).
  - A packing: ACES display RGBA (unchanged).

- `gen-astro-mechanical-quantum-furnace-engine`
  - Kept verbatim: refracted furnace core, meshing/counter-rotation gear train, piston-chuff exhaust.
  - Added: tooth-root heat-check crazing (`craze`), anvil spark shower (`sparkRing`/`sparks`).
  - A packing: raw HDR trail RGB + semantic alpha (unchanged).

- `gen-audiovisual-mandelbulb-raymarcher`
  - Kept verbatim: escape-time strata, DE soft shadows + AO, trap-colored silhouette halo.
  - Added: cusp-caustic glints (`cusp`), chromatic wedge dispersion (`wedge`-modulated CA).
  - A packing: raw HDR scene RGB + semantic alpha (unchanged).

- `gen-auroral-ferrofluid-monolith`
  - Kept verbatim: aurora sheath/co-wind/pole behavior and spike-tip corona identity.
  - Added: cusp-knot aurora whorls (`cusp`), substorm breakup arc curtains (`breakup`).
  - A packing: ACES display RGBA (unchanged).

- `gen-bioluminescent-chrono-plasma-astro-owl`
  - Kept verbatim: frame-dragged sky, lattice plumage etching, nebula-dissolve fog.
  - Added: facial-disk diffraction rings (`disk`), wingtip plasma-vortex shed (`vortex`).
  - A packing: raw HDR linear RGB + semantic alpha (unchanged).

- `gen-bioluminescent-cyber-aether-void-seahorse`
  - Kept verbatim: sagittal fin-ray membrane and fold-tree chromatophore cascade behavior.
  - Added: electroreceptor snout whiskers (`whisk`), brood-pouch pulse bloom (`pouch`/`pouchPulse`).
  - A packing: raw HDR linear RGB + semantic alpha (unchanged).

- `gen-bismuth-singularity-loom-engine`
  - Kept verbatim: six-sector self-assembly clocks, proper-time shear, singularity shadow/capture.
  - Added: terrace-edge cathodoluminescence (`edge`), photon-sphere shear arcs (`ringBand`/`ringArc`).
  - A packing: raw HDR linear RGB + semantic alpha (unchanged).

- `gen-chromodynamic-plasma-collider`
  - Kept verbatim: bunch-crossing bursts, magnetic steering + betatron wobble, momentum dispersion.
  - Added: synchrotron sideband comb (`sideband`), Cherenkov wake cones (`wake`).
  - A packing: raw HDR radiance RGB + semantic alpha (unchanged).

## Validation

- Scoped naga-wasm: 10/10 valid.
- Scoped precommit gate: 10/10 pass, no pasted headers.
- `npm run audit:extrabuffer`: pass (0 new violations).
- `npm run audit:dead-sliders -- --files <10 ids>`: pass (0 new dead sliders; 10 definitions scanned).
- `node scripts/generate_shader_lists.js` + `node scripts/check_duplicates.js`: pass.
- `npm test -- --watchAll=false --ci`: pass (`134` suites passed, `1033` passed / `1034` total tests).
- `SKIP_WASM_BUILD=1 npm run build`: pass.
