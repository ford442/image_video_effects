# Changelog — gen-nebular-chrono-astrolabe (Batch 33)

Lines: 163 → 207.

- Corrected mouse orientation, added spring orbit and click gravity rings, and
  bounded the march budget.
- Removed an accumulated-but-invisible nebula loop and replaced it with an
  eight-sample visible nebular layer.
- Added safe steps, exact feedback loads, ACES output, and near-is-one depth.

Validation: focused WGSL/Naga, contracts, and strict extraBuffer checks pass.
Real-GPU visual QA remains external.
