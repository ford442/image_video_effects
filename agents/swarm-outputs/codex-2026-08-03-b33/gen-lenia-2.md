# Changelog — gen-lenia-2 (Batch 33)

Lines: 168 → 209.

- Repaired the simulation loop so dataTextureC is prior four-species state,
  dataTextureA is next state, and writeTexture is colored presentation.
- Added normalized integer-neighbor kernels, deterministic sparse seeding,
  press-only feeding, and click inoculation.
- Added neighboring-state chroma and density-derived alpha/depth while
  preserving all saved controls.

Validation: focused WGSL/Naga, contracts, and strict extraBuffer checks pass.
Real-GPU visual QA remains external.
