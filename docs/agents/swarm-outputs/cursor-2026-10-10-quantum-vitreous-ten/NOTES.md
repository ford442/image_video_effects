# Batch Notes — quantum-vitreous-ten

All target shaders in this batch now use `#include "_prelude.wgsl"` (9 migrated, 1 already migrated).  
Saved `params` were preserved for all 10 matching definitions.

## Per-shader upgrade notes

- `gen-quantum-resonance-lattice`
  - Kept verbatim: repeated octahedral lattice map, chromatic channel march, forward-travel identity.
  - Added: resonant band-splitting halos (`resonanceHalo`), nodal-plane standing-wave sheets (`nodalSheets`).
  - Also aligned floor: plasma audio source, ACES display write, semantic alpha, normalized depth.
  - A packing: ACES display RGBA.

- `gen-radiant-chrono-glass-nautilus`
  - Kept verbatim: chamber septa + siphuncle + chamber tide structure and slider roles.
  - Added: septal suture scallops (`scallop`), nacre growth striae (`striae`).
  - A packing: ACES display RGBA.

- `gen-rgb-diffraction`
  - Kept verbatim: multi-slit superposition, single-slit envelope, blaze steering model.
  - Added: Talbot self-imaging replicas (`talbot`), order-selective grating lobes (`lobes`).
  - A packing: ACES display RGBA.

- `gen-sentient-holographic-neuro-lace-matrix`
  - Kept verbatim: gyroid flythrough, breathing wave, bioluminescent haze, held-node bloom behavior.
  - Added: re-entrant synaptic vortex loops (`loopRing`/`loopSpin`), myelin conduction bead trains (`beads`/`strand`).
  - A packing: ACES display RGBA.

- `gen-vitreous-chrono-chandelier`
  - Kept verbatim: pendulum crystal placement, refractive split, temporal polish/chromatic path.
  - Added: phase-locked pendulum cluster modulation (`cluster` angle term), floor caustic web projection (`web`).
  - A packing: ACES display RGBA.

- `gen-vitreous-quantum-lotus-singularity`
  - Kept verbatim: lotus fold/petal structure, thin-film shell, vein inlay, singularity core behavior.
  - Added: alternating petal torsion chirality (`twist`), photon-sphere shear arcs (`arcBand`/`shear`).
  - A packing: raw normal/material fields in A (preserved existing convention).

- `gen-translucent-nebula`
  - Kept verbatim: layered nebula accumulation, FBM+Worley cloud basis, starfield and temporal smooth.
  - Added: Rayleigh-Taylor plume fingers (`plume`), ionization-front shell bands (`ionFront`/`ionBand`).
  - A packing: ACES display RGBA.

- `gen-thermal-rainbow-topography`
  - Kept verbatim: domain-warped topography, contour system, diffusion feedback, ripple heat behavior.
  - Added: watershed drainage channels (`channel` from curvature+slope), saddle-point eddy blooms (`saddle`/`eddy`).
  - A packing: terrain color + diffused height field in A.

- `gen-torus-knot-rainbow`
  - Kept verbatim: analytic knot SDF, Julia trap halo, domain-warped background, temporal trails.
  - Added: Kelvin wave packets along arc (`kelvin`), braid-crossing flare bursts (`crossingBurst`).
  - A packing: ACES display RGBA.

- `gen-voronoi-crystal`
  - Kept verbatim: Voronoi cell core logic, triple junctions, facet edge/frost/specular framework.
  - Added: dislocation glide lines (`dislocation`), annealing front bloom (`annealBand`).
  - A packing: ACES display RGBA.

## Validation

- Scoped naga-wasm: 10/10 valid.
- Scoped precommit gate: 10/10 pass, no pasted headers.
- `npm run audit:extrabuffer`: pass (0 new violations).
- `npm run audit:dead-sliders -- --files <10 ids>`: pass (0 new dead sliders; scanner reports 5 definitions in this mixed-schema set).
- `node scripts/generate_shader_lists.js` + `node scripts/check_duplicates.js`: pass.
- `npm test -- --watchAll=false --ci`: pass (`134` suites passed, `1033` passed / `1034` total tests).
- `SKIP_WASM_BUILD=1 npm run build`: pass.
