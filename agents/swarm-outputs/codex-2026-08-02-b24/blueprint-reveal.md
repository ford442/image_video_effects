# Batch 24: `blueprint-reveal`

- Added a critically damped reveal brush using only `extraBuffer[133..138]`.
- Added guarded click-seeded ink blooms and luminous drafting rings at normalized
  ripple positions.
- Added per-tile FFT ink voices while preserving the Sobel and depth-hatch core.
- Kept raw temporal reveal state in `dataTextureA`; no display color or tonemap
  was introduced into the mask feedback path.
- Preserved all four source parameters exactly and added indexed
  `updatedParams` plus truthful click/depth metadata.
