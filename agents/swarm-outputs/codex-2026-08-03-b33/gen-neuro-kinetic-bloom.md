# Changelog — gen-neuro-kinetic-bloom (Batch 33)

Lines: 157 → 190.

- Added spring-driven bloom positioning, side tendrils, and click-triggered bloom
  rings without changing the four saved controls.
- Hardened normalization and ray steps, expanded material bands, and retained
  the shader's real geometric depth output.
- Confined persistent interaction state to `extraBuffer[133..138]`.

Validation: focused WGSL/Naga, contracts, and strict extraBuffer checks pass.
Real-GPU visual QA remains external.
