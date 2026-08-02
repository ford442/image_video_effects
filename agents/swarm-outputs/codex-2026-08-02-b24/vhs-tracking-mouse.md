# Batch 24: `vhs-tracking-mouse`

- Added spring-damped tracking-head motion in safe persistent state slots.
- Added guarded click damage localized by both scanline band and click X position;
  damage drives tape shear, hiss, and tracking-loss flare.
- Added per-row FFT hiss voices and made the displaced depth sample follow the
  same UV as the damaged image.
- Preserved display-color ownership in `dataTextureA` and bounded static output.
- Preserved all four source parameters exactly and added indexed
  `updatedParams` plus click-reactive metadata.
