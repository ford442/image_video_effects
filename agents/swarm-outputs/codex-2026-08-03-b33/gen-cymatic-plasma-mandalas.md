# Changelog — gen-cymatic-plasma-mandalas (Batch 33)

Lines: 150 → 178.

- Standardized the workgroup to 16x16x1 and corrected the double-normalized
  mouse mapping.
- Added spring interaction and click nodes while keeping symmetry order stable;
  audio now animates the field rather than changing its topology.
- Added safe density math, integer feedback/depth loads, and real relief depth.

Validation: focused WGSL/Naga, contracts, and strict extraBuffer checks pass.
Real-GPU visual QA remains external.
