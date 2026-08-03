# Changelog — gen-silica-tsunami (Batch 33)

Lines: 174 → 208.

- Corrected mouse-down and world-space mapping, then added spring motion and
  click shard/ring fractures.
- Wired Glass Refraction into real IOR-driven transmission and corrected
  Particle Density to inverse spacing without changing its saved default.
- Added bounded steps/output, semantic alpha, and real near-is-one depth.

Validation: focused WGSL/Naga, contracts, and strict extraBuffer checks pass.
Real-GPU visual QA remains external.
