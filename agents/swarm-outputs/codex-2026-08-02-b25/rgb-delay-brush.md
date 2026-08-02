# Batch 25: `rgb-delay-brush`

- Corrected the header from a physical-science claim to a scoped,
  Beer-Lambert-inspired artistic absorption model.
- Added spring-weighted brush motion and guarded click-stamped temporal masks.
- Added valid red/green/blue FFT voices to channel response while preserving raw
  temporal RGBA feedback in `dataTextureA`.
- Guarded zero-radius brush behavior, preserved all source parameters, and added
  indexed `updatedParams` plus truthful temporal/audio/click metadata.
