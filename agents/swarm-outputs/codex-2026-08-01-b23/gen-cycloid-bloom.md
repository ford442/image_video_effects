# Batch 23: `gen-cycloid-bloom`

- Reduced per-pixel curve work from 241 tests × 5 layers (1,205) to a 64-step
  coarse search plus exactly eight local refinement samples per layer (360).
- Mouse pull now has a nonzero baseline and no longer requires bass energy.
- Added guarded click waves that modulate petal radius/phase and a separate
  valid FFT voice (`plasmaBuffer[1..8]`) for each layer's shimmer/hue.
- Preserved the five-layer hypotrochoid identity, display-color feedback in
  `dataTextureA`, ACES output, depth packing, and all parameter defaults.

