# interactive-ripple v2 Upgrade Notes

## Swarm Synthesis
- **Algorithmist**: Added 2D wave equation solver with dispersion — different frequencies travel at different speeds via `sqrt(waterDepth)` and `treble`-modulated dispersion frequency. Huygens wavelet superposition from each ripple source with phase-shifted secondary wavelets. Added boundary reflection damping via `boundReflect`.
- **Visualist**: Chromatic dispersion on ripple crests (RGB sampled at different offsets), caustic highlights in constructive interference zones, HDR bloom, ACES tone mapping, subsurface scattering in water.
- **Interactivist**: Bass drives wave frequency (adds to waveCount), mouse drops stones via ripple array, depth controls water depth (affects wave speed via `sqrt(waterDepth)`).
- **Optimizer**: Fixed max 50 ripple loop (same as v1), branchless boundary damping with smoothstep, reused sampleUV for chroma splits.

## Alpha Semantics
`finalAlpha = ripple_height * dispersion_intensity * depth * 2.5 + 0.55 + caustic * 0.3`
Alpha encodes ripple height, chromatic dispersion strength, and depth.

## Line Count
129 lines

## Changes from v1
- Replaced simple sine ripple with wave equation + dispersion
- Added Huygens wavelet superposition (phase-shifted secondary waves)
- Added boundary reflection damping
- Added chromatic dispersion on crests
- Added caustic highlights and subsurface scattering
- Added ACES tone mapping
- Alpha now semantic (was clamped 0.68 + wetSpec)

## Validation
naga: PASS
