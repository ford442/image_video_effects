# Changelog — gen-superfluid-quantum-foam (Batch 33)

Lines: 150 → 191.

- Made Speed drive bounded field evolution while leaving the camera stable.
- Added spring repulsion, click cavitation shells, safe march steps, ACES output,
  semantic alpha/depth, and exact feedback loads from dataTextureC.
- Preserved the four saved controls and confined new state to
  `extraBuffer[133..138]`.

Validation: focused WGSL/Naga, contracts, and strict extraBuffer checks pass.
Real-GPU visual QA remains external.
