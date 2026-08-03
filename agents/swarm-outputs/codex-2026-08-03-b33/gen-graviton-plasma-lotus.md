# Changelog — gen-graviton-plasma-lotus (Batch 33)

Lines: 173 → 211.

- Repaired normalized mouse-to-world conversion and added spring gravity plus
  click pulses.
- Hardened raymarch steps, safe normalization, multiband materials, ACES output,
  and bounded surface/rim glow in place of inverse ray-distance bloom.
- Added exact temporal feedback and real near-is-one hit depth.

Validation: focused WGSL/Naga, contracts, and strict extraBuffer checks pass.
Real-GPU visual QA remains external.
