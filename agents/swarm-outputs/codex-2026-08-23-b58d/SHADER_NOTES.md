# Batch 58D shader notes

- `spectral-bleed-confinement`: edge channels follow a sprung curl focus while
  bounded click fronts seed exact-C spectral afterglow.
- `spectral-flow-structure`: Temporal Smoothing now controls an actual exact-C
  display-history blend; audio rotates and stretches coherent LIC flow.
- `spectral-glitch-sort`: removes the all-thread storage race and fake
  `plasmaBuffer[1..8]` FFT assumption; block tears leave exact display trails.
- `spectral-smear`: flow-advected history is quantized to clamped integer loads;
  clicks bloom paint independently of held pointer strokes.
- `spectral-vortex`: A packs `phase, curl.x, curl.y, energy`; output depth is
  strictly the source depth and never private temporal state.
- `spectral-waves`: premultiplied composition and sprung origin remain intact;
  caustics persist through exact A/C display history and use FFT `[5..132]`.
- `spectrogram-displace`: synthetic oscillators are removed. Live plasma bands
  and FFT bins form a horizontally scrolling spectrogram in A.
- `spectrum-bleed`: preserves the four slider positions and `[133..138]` spring
  while replacing filtered persistence and opaque history alpha.
- `data-moshing`: A is raw offset/confidence/age state; source pixels are sampled
  through that field and tone-mapped only for the display output.
- `datamosh`: A alone packs motion/age/strength. Predicted pixels come from the
  current source, so host A→C ownership no longer destroys a B smear buffer.
