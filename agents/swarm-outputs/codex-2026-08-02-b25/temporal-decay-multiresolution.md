# Batch 25: `temporal-decay-multiresolution`

- Made the advertised mouse behavior real with a spring-following temporal lens
  stored only in `extraBuffer[133..138]`.
- Added guarded click echo rings that refract history lookups and locally favor
  the four-timescale result.
- Added regional FFT decay voices and wired the previously unused treble signal
  into the slow timescale.
- Preserved binding 13, the eight-layer history indexing, read-only
  `extraBuffer[4]` history head, channel packing, and all source parameters.
