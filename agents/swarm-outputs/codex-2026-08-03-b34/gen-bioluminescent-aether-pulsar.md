# Changelog — gen-bioluminescent-aether-pulsar (Batch 34)

Lines: 195 → 238.

- Removed the generic post-effect remapping so Spin Rate, Beam Intensity,
  Accretion Density, and Color Shift drive their advertised roles directly.
- Corrected centered mouse orbit, bounded volumetric beam glow, signed march
  steps, and surface normals; added click shocks and temporal polish.
- Added the formerly missing A output plus semantic alpha and real hit depth.

Validation: focused WGSL/Naga, contracts, and strict extraBuffer checks pass.
Real-GPU visual QA remains external.
