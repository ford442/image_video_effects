# spectral-mesh v2 — Upgrade Notes

## Summary
Upgraded from 79 lines to 136 lines. All 4 swarm perspectives synthesized.

## Algorithmist Changes
- Added Delaunay-style triangulation simulation via triangular edge detection (`triA`, `triB` from `grid.x + grid.y`)
- Adaptive mesh density based on image gradient magnitude: `imageGradient()` samples ±eps in X/Y, `adaptiveDensity = densityBase * (1.0 + gradMag * 2.5 + audio.x * 0.8)`
- Spectral coloring per vertex uses physical wavelength-to-RGB conversion (`spectralWavelength()`) with 380–780nm mapping

## Visualist Changes
- Chromatic vertex coloring by wavelength via `spectralWavelength(fract(waveParam))`
- Wireframe glow: `line * (0.12 + 0.28 * audio.z) + triLine * (0.06 + 0.14 * audio.x)`
- HDR bloom on glow: `glow^2 * vec3(0.45, 0.55, 0.75)`
- ACES filmic tone mapping via `acesFilm()`
- Subsurface scattering on mesh faces: `diagonal * (0.08 + 0.18 * pull)`

## Interactivist Changes
- Bass drives mesh subdivision level via `adaptiveDensity` multiplier from `audio.x`
- Mouse attracts mesh vertices: `attract = (mouse - uv) * pull * 0.06 * (1.0 + audio.y * 0.6)`
- Depth controls perspective foreshortening: `foreshorten = 1.0 - depth * 0.35` applied to grid UV

## Alpha Strategy
`finalAlpha = meshDensity * spectralIntensity * depth * 2.2`, clamped 0.12–0.94
- meshDensity: `(line + triLine + diagonal) * 0.5`
- spectralIntensity: `length(spectral)`
- depth: read from `readDepthTexture`

## Naga Status
✅ Validation successful
