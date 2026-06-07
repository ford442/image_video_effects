# fractal-noise-dissolve — Kimi Batch C Notes

## What I Changed
- Added domain-warped FBM (4 octaves) for more organic dissolution patterns.
- Bass triggers edge glow around the dissolve boundary.
- Depth fades the dissolution (background dissolves first).

## What I'm Proud Of
The domain warping makes the dissolve boundary look like ink bleeding into paper rather than a mechanical threshold — much more organic.

## What Might Need a Human Eye
- 4-octave fbm + domain warp is computationally expensive — may need LOD on mobile.
