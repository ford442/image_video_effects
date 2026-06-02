# luminance-wind — Kimi Batch E Notes

## Changes Made
- Added curl-noise wind field (3-octave fbm-based curl2D) for organic turbulence
- Added chromatic drift: R channel drifts 1.1x velocity, B channel 0.9x
- Added audio gust strength: bass scales wind speed via `bass_env()`
- Added depth parallax: depthLayer scales wind speed (near = slower, far = faster)
- Temporal feedback via `dataTextureC` for persistent trails

## Wow Factor
- Wind no longer moves uniformly; curl-noise creates swirling vortices
- Chromatic drift makes light pixels leave colorful contrails

## Risks
- Curl2D function uses 4 fbm evaluations per pixel; may be heavy on low-end GPUs
- `dataTextureC` read for chromatic drift doubles texture samples per channel
