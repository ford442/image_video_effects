# Changelog — gen-fractal-clockwork (Batch 33)

Lines: 153 → 186.

- Corrected gear-cell parity and hardened the raymarch with positive bounded
  steps.
- Added spring orbit control, click torque waves, multiband material polish,
  ACES output, and exact temporal feedback loads.
- Emits semantic alpha and near-is-one hit depth with zero on misses.

Validation: focused WGSL/Naga, contracts, and strict extraBuffer checks pass.
Real-GPU visual QA remains external.
