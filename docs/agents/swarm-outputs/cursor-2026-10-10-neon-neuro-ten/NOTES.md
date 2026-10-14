# Batch Notes — neon/neuro ten

- `gen-neon-plasma-biomechanical-hive`
  - Kept: hive flythrough, brood-cell + spore identity, peristaltic tube pulses, slider roles.
  - Added: chitin valve irises (`irisPhase`/`irisRing`); trophallactic plasma bridges (`bridge`/`troph`).
  - Packing: ACES display RGBA in A; HDR trail recovery via `acesInverse` unchanged.

- `gen-neon-plasma-chrono-bloom`
  - Kept: radial time lag and dual-sheet filament march architecture.
  - Added: phase-slip caustics (`phaseSlip`/`caustic`); rotating sepal ribs (`theta`/`ribs`/`chronoGlow`).
  - Packing: ACES display RGBA in A.

- `gen-neural-bioluminescence-matrix`
  - Kept: Ranvier spikes, aequorin->GFP transfer, calcium click-wave behavior.
  - Added: astrocyte calcium tide (`gliaWave`/`gliaGlow`); vesicle bouton scintillation (`vesicle`/`vesicleGlow`).
  - Packing: ACES display RGBA in A.

- `gen-neural-fractal`
  - Kept: neural activation fractal path, dendritic growth front, firing-rate glow.
  - Added: inhibitory surround (`inhibitoryRing`); Hebbian feedback persistence (`hebbian` with `dataTextureC` readback).
  - Packing: ACES display RGBA in A.

- `gen-neural-network-glow-synaptic-pulse`
  - Kept: quantal release clouds, AP refractory waveform, evoked click rings.
  - Added: conduction-delay ladders (`conductionDelay`); astrocytic uptake halo (`uptake`).
  - Packing: ACES display RGBA in A.

- `gen-neuro-cosmos`
  - Kept: voronoi web + soma blend, saltatory + IAF neuron dynamics.
  - Added: activity pruning shadows (`prune`); Hebbian reinforcement (`reinforce` from C feedback).
  - Packing: ACES display RGBA in A.

- `gen-neuro-fluid-plasma-lotus`
  - Kept: lotus SDF morphology, phyllotaxis core, flux-rope field glow.
  - Added: capillary petal venation (`capillary`); reconnection plumes (`reconnection`).
  - Packing: ACES display RGBA in A.

- `gen-neuro-kinetic-bloom`
  - Kept: branching flora scaffold + saltatory pulse logic.
  - Added: myelin pearling trunk radius modulation (`pearling`/`trunkRadius`); synaptic bouton crowns (`boutonA`/`boutonB`).
  - Packing: ACES display RGBA in A.

- `gen-neuro-kinetic-liquid-gold-lotus`
  - Kept: conductive Fresnel metal response, phyllotaxis anther firing, torque history advection.
  - Added: capillary rivulets (`rivulet`); Kelvin-Helmholtz shear rolls (`shearRoll`).
  - Packing: ACES display RGBA in A.

- `gen-neutron-star-magnetic-spindle`
  - Kept: dipole-line + beam architecture, lensing, jets/disk volumetrics.
  - Added: polar-cap spark carousel (`polarCap`/`carousel`/`spark`); striped current sheet (`sheetPlane`/`stripes`/`sheet`).
  - Packing: ACES display RGBA in A.

## Structural Gates

- Naga (scoped): 10/10 valid via `node scripts/verify-naga-wasm.mjs --files ...`.
- Prelude migration: all 10 now use `#include "_prelude.wgsl"` via `scripts/migrate_to_prelude.py`.
