# Batch Notes — prismatic-photonic-ten

All ten shaders were migrated to `#include "_prelude.wgsl"` before creative edits.
Saved `params` were kept unchanged in all corresponding definition JSON files.

## Per-shader notes

- `gen-photonic-crystal-brain`
  - Kept verbatim: crystal lattice SDF + Bragg color path + waveguide spike path + slider semantics.
  - Added: defect-cavity resonator blooms (`cavityResonance`), synaptic junction avalanche flashes (`junctionAvalanche`).
  - A packing: ACES display RGBA.

- `gen-plasma-psychedelic-wormhole`
  - Kept verbatim: tunnel coordinate construction, click lens masses, photon-sphere subrings, HDR trail decode/encode.
  - Added: ergosphere-style frame-drag shear (`dragShear`/`draggedTheta`), Kelvin-Helmholtz wall billows (`billows`).
  - A packing: ACES display RGBA, exact `dataTextureC` read + inverse ACES.

- `gen-prismatic-aether-loom`
  - Kept verbatim: KIFS weave family, plain-weave interlacing, thin-film thread sheath, radial history trails.
  - Added: twill-diagonal shuttle drift (`twill`), selvedge knot sparks (`knot`).
  - A packing: ACES display RGBA.

- `gen-prismatic-bismuth-lattice`
  - Kept verbatim: bismuth DE fold workflow, hopper terraces, oxide/interference film, oxidation ripple fronts.
  - Added: screw-dislocation terrace spirals (`screw`), Kikuchi-like diffraction bands (`kikuchi`).
  - A packing: ACES display RGBA.

- `gen-prismatic-cyber-aether-void-kitsune`
  - Kept verbatim: kitsune body/tail/shard/ring composition, fox-fire + thin-film tails, existing slider roles.
  - Added: ionized tail-bridge streamers (`tailBridgeStreamers`), ring-rune moire gate interference (`moire` in ring material).
  - A packing: ACES display RGBA.

- `gen-prismatic-cyber-aurora-astral-dragonfly`
  - Kept verbatim: dragonfly SDF silhouette, wing thin-film + venation, attractor particles, auroral background path.
  - Added: leading-edge vortex sheet glow (`lev`), abdominal segment bioluminescence (`abdomenGlow`).
  - A packing: ACES display RGBA.

- `gen-prismatic-cyber-auroral-manta-swarm`
  - Kept verbatim: swarm orbit/orientation logic, manta SDF, chordwise wave, countershading + chevrons + ventral spots.
  - Added: ventral gill-arch bioluminescence (`mantaGillArches`), ram-ventilation wake ribbons (`mantaWakeRibbon`).
  - A packing: ACES display RGBA.

- `gen-prismatic-cyber-chrono-nebula-peacock`
  - Kept verbatim: body/plumage map path, barbule thin-film, zoned ocellus model, nebula accumulation.
  - Added: rachis-barb shaft branching (`rachisBarbs`), chrono-precession ocellus halos (`ocellusHalo`).
  - A packing: ACES display RGBA.

- `gen-prismatic-cyber-chrono-void-kitsune`
  - Kept verbatim: kitsunebi wisps, Cauchy body dispersion, material split (body/tails/rift/dust), temporal smear path.
  - Added: caudal-band tail caustics (`band`/`caustic`), helical rift current sheets (`sheet` in volumetric density).
  - A packing: ACES display RGBA.

- `gen-prismatic-cyber-chrono-void-tortoise`
  - Kept verbatim: tortoise anatomy map, scute annuli, hawksbill mottling, abyss motes/ripple ring base.
  - Added: triradiate osteoderm sutures (`suture`), magnetotactic plankton lanes (`planktonLane`/`planktonGlow`).
  - A packing: ACES display RGBA.

## Validation

- Naga wasm (scoped, 10 files): 10/10 valid.
- `npm run audit:extrabuffer`: pass (0 new violations).
- `npm run audit:dead-sliders -- --files <10 ids>`: pass (0 new dead sliders).
- `node scripts/generate_shader_lists.js` + `node scripts/check_duplicates.js`: pass.
- `npm test -- --watchAll=false --ci`: pass.
- `SKIP_WASM_BUILD=1 npm run build`: pass.
