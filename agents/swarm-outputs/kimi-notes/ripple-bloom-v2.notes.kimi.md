# ripple-bloom v2 Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Huygens wavelet construction with 3 frequency layers and dispersion (`rippleSpeed * (1.0 + f * 0.15)`). Each frequency decays at a different rate.
- **Visualist**: Chromatic dispersion on ripple crests, HDR bloom on constructive interference, subsurface scattering in troughs (`sss = trough * rippleHeight * 0.15`), ACES tone mapping.
- **Interactivist**: Bass drives ripple frequency/amplitude, mouse drops stones creating circular waves, depth controls water depth affecting ripple speed (`waterDepth = mix(0.3, 1.0, 1.0 - depth)`).
- **Optimizer**: Loop of 3 for wavelets, single depth sample, clamped UVs.

## Alpha Semantics
`clamp(rippleHeight * dispersionIntensity * depth * 2.0, 0.15, 0.95)` — ripple_height × dispersion_intensity × depth.

## Key Changes
- New helpers: `acesToneMap`, `hash21`
- `depth-aware` feature added
- Line count: 81 → 129
- Naga: PASS
