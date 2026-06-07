# luma-smear-interactive — Kimi Batch E Notes

## Changes Made
- Added chromatic smear: R lags (1.2x velocity), B leads (0.8x) creating color trails
- Added curl-noise turbulence for organic smear direction variation
- Added audio gust: bass pushes smear outward from mouse position
- Added depth viscosity: depth scales smear strength
- Added treble shimmer to smeared pixels
- Temporal feedback via `dataTextureC`

## Wow Factor
- Bright moving objects now leave rainbow contrails instead of monochrome ghosts
- Audio gusts make the smear explode outward on bass drops

## Risks
- Chromatic smear requires 3x `dataTextureC` samples per pixel (R, G, B at different UVs)
- Curl turbulence may cause smear to loop back on itself unexpectedly
