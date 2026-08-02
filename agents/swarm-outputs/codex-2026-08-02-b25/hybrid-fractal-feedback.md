# Batch 25: `hybrid-fractal-feedback`

- Fixed all four mislapped control mappings: JSON Zoom, Feedback, RGB Delay, and
  Color Cycling now drive those exact WGSL behaviors.
- Replaced the unsafe 256-entry palette read with a bounded cosine palette plus
  valid per-region FFT bins 1–8.
- Added spring Julia steering, guarded click-local complex-parameter kicks,
  actual temporal RGB-offset sampling, and fractal/click relief depth.
- Preserved accumulated feedback in `dataTextureA` and all source parameter
  contracts; added indexed `updatedParams` and truthful interaction metadata.
