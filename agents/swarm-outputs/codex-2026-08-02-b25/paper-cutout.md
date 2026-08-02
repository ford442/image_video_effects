# Batch 25: `paper-cutout`

- Removed the top-left-pointer-as-uninitialized bug and added spring-damped light
  tracking with a zero-distance-safe direction.
- Added guarded click-punched emboss rings and valid per-layer FFT shimmer.
- Bounded paper emission and replaced depth passthrough with real layer/ring
  relief, earning the existing depth-aware feature claim.
- Preserved display RGBA ownership and all source parameters; added indexed
  `updatedParams`, click metadata, and `supportsDepth`.
