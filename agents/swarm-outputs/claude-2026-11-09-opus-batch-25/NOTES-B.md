# opus/batch-25 — fork B notes

## holographic-edge-ripple (2nd pass)
Kept verbatim: laplacian/sobel kernels, Fresnel orders, grating streaks, depth parallax layer, params, A packing (linear pre-ACES, 30% edge-gated C), click fronts.
Ideas in diff: ±1 diffraction-order ghosts (orderLight, per-channel λ offsets along pointer-rotated gAxis); wavefront dispersion (displaced R/G/B sampled at dispBase*dispersion / dispBase / dispBase/dispersion); reconstruction speckle (speckle term multiplies diffraction, slides with mouse).
Render: meanA 0.975 (unchanged), meanL 0.49→0.52, rainbow ghost edges visible around the disc.

## audio-reactive-temporal-decay
Rescues: anamorphic streak was a fixed vertical white line at x=0.5; C read with filtering sampler (now exact textureLoad); A stored graded*alpha colour (vignette/scanline/grade compounded each frame → HEAD default ran dark: meanL 0.10, meanA 0.67); no ACES (added on display); empty history adopts live frame.
Ideas in diff: row bright-pass anamorphic smear (13-tap); spectral persistence (eBand thirds → decayRgb); bass push (histUv zoom).
A packing: linear pre-grade trail RGBA. Render at defaults: meanL 0.47, meanA 1.0, no NaN.

## pixel-sort-glitch
Rescues: sortWindow was ≈identity (one bubble pass + nearest-luma pick); dead extraBuffer[133..136] spring (pointer now live); dead plasmaBuffer[1..8]; alpha 0.24 wash → 0.85–1.0 semantic coverage.
Ideas in diff: spanSort (anchored span rank sort); FFT-banded span length (extraBuffer[5+band*6]); span-end R/B channel slip.
A packing unchanged. Renders H/V modes show visible sorted streaks out of the disc; meanA 0.90.
