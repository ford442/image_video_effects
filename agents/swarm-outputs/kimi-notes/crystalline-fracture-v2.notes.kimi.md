# crystalline-fracture v2 Upgrade Notes

## Summary
Upgraded from 107-line Voronoi crystal to 170-line fracture mechanics simulation with stress intensity factor K, crack branching, percolation connectivity, hackle marks, thin-film iridescence, and subsurface scattering.

## Algorithmist Perspective
- Stress field: bass loading + mouse point stress + exponential proximity field.
- Fracture toughness = mids-driven threshold.
- Catastrophic failure events triggered by treble spikes.
- Stress intensity factor K = stress × sqrt(crackLength).
- Crack propagation: step(toughness, K).
- Branching: step(1.3 × toughness, K) × hash.
- Percolation connectivity boosts stress from previous crack density.
- Temporal stress memory stored in dataTextureA.r, crack density in dataTextureA.g.

## Visualist Perspective
- Thin-film iridescence on fracture surfaces (sinusoidal hue shift).
- Hackle marks: dual ridged patterns modulated by crack density.
- Subsurface scattering approximation near cell edges.
- Chromatic aberration on internal reflections (R/B edge offsets).
- HDR bloom at crack tips.
- ACES tone mapping.
- Depth reduces cell interior brightness (thickness perspective).

## Interactivist Perspective
- Bass drives stress loading (crack speed).
- Mids control fracture toughness.
- Treble triggers catastrophic failure (2× stress boost).
- Mouse applies point stress (smoothstep + exponential field).
- Depth controls crystal thickness perspective (cell density + color fade).

## Alpha Semantics
`alpha = crack_density × stress_intensity × depth + edge × 0.15`
Never uses opaque 1.0.

## Technical
- Lines: 170
- Naga: ✅ Valid
- No readTexture sampling.
- Uses dataTextureC for temporal crack state feedback (stress, crackDensity).
- dataTextureA stores next-frame state (stress, crackDensity, 0.0, alpha).
