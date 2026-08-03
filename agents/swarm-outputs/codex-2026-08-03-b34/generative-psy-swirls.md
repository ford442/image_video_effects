# Changelog — generative-psy-swirls (Batch 34)

Lines: 189 → 207.

- Added spring-following vortex control while preserving the existing domain
  warp, hue fan, and saved `params`/`updatedParams` arrays.
- Guarded ripple count and age, replaced filter-dependent C sampling with exact
  loads, and retained bounded A display history.
- Added explicit 16x16x1 metadata, semantic alpha, and generated swirl depth.

Validation: focused WGSL/Naga, contracts, and strict extraBuffer checks pass.
Real-GPU visual QA remains external.
