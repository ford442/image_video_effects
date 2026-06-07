# soft-vignette-bloom v2 — Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Multi-scale Gaussian blur pyramid (3 scales: 1.0, 2.5, 5.0 with weighted contributions). Superellipse vignette using `pow(pow(abs(dx), 2.5) + pow(abs(dy), 2.5), 1/2.5)`.
- **Visualist**: Anamorphic bloom streaks on bright highlights (horizontal Gaussian stretch). Film grain via `hash12`. Split-tone shadows (purple/blue tint). ACES tone mapping. Depth-driven haze mixing.
- **Interactivist**: Bass lowers bloom threshold dynamically. Mouse shifts vignette center (`vignetteCenter = mix(0.5, mouse, 0.5)`). Depth controls haze amount (`depth` read from `readDepthTexture`).
- **Optimizer**: 5x5 samples per scale, 3 scales total = 75 samples max. Streak uses 17 horizontal taps with exponential falloff. Early boundary exit.

## Alpha Semantic
`alpha = clamp(bloomEnergy * vignette * 2.0 + baseAlpha * 0.3, 0.0, 1.0)`
- `bloomEnergy`: accumulated luminance from multi-scale bloom
- `vignette`: superellipse aperture factor
- Combines post-process energy with original content alpha

## Lines
138 lines (upgraded from ~90)

## Bindings
Canonical 13-binding header, exact `Uniforms` struct, `@workgroup_size(16, 16, 1)`.

## Chunks Used
- `aces_approx` (filmic tone mapping)
- `hash12` (film grain noise)

## Params
1. Vignette Strength (`zoom_params.x`)
2. Bloom Radius (`zoom_params.y`)
3. Haze Amount (`zoom_params.z`)
4. Bloom Intensity (`zoom_params.w`)
