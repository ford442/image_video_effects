# Batch 23: `fractal-noise-dissolve`

- Corrected the shader header category from `visual-effects` to literal `image`.
- Added a critically damped erosion center in `extraBuffer[133..138]` and
  guarded click-seeded expanding dissolve rings.
- Applied a hue-preserving soft knee to burn emission before compositing.
- Reused the single sampled depth value for depth fade and depth output.
- Preserved the domain-warped FBM identity and `dataTextureA` display packing;
  added indexed `updatedParams` copied from the untouched source params.

