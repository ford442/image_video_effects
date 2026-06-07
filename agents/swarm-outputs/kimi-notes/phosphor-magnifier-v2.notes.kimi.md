# phosphor-magnifier v2 — Upgrade Notes

## Summary
Upgraded from 77 lines to 129 lines. All 4 swarm perspectives synthesized.

## Algorithmist Changes
- Added P22 phosphor decay model with per-RGB exponential time constants (`phosphorDecay = vec3(0.92, 0.88, 0.95)`, decay rates `vec3(1.2, 0.8, 1.6)`)
- Replaced simple magnification with barrel distortion (`centered * (1.0 + 0.18 * lensMask * |centered|^2)`)
- Added per-channel chromatic aberration (R/G/B sampled at `caStrength = 0.004 * lensMask * zoomLevel` offsets)
- Each channel gets independent zoomed + snapped UV for triad separation

## Visualist Changes
- Added CRT shadow mask aperture-grille via `shadowMask()` function (RGB subpixel stripes)
- Scanline beats: base scanline `sin(y * 0.55)` multiplied by audio-driven beat `sin(y * 40 + time * 12)`
- HDR bloom on bright magnified areas: `brightness^2 * glow * lensMask * audio`
- ACES filmic tone mapping via `acesFilm()`
- Afterimage trails: reads previous frame from `dataTextureC`, blends at 12% with 22% mix factor inside lens

## Interactivist Changes
- Bass (`audio.x`) drives phosphor excitation rate: `bassExcite = 1.0 + audio.x * 1.2`
- Mouse positions the magnifier (unchanged centering)
- Depth controls magnification power: `depthMag = mix(1.0, 1.0 + depth * 2.5, lensMask)` applied to zoom divisor

## Alpha Strategy
`finalAlpha = exciteAlpha * magnification * depth * 3.5`, clamped 0.15–0.96
- exciteAlpha: average of RGB decay excitation
- magnification: `lensMask * zoomLevel * 0.1`
- depth: read from `readDepthTexture`

## Naga Status
✅ Validation successful
