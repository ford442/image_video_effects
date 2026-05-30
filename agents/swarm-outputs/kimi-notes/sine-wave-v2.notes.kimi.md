# sine-wave v2 Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Traveling wave packets with group velocity ≠ phase velocity via `groupVel = sin(phase * 0.5 + time * speed * 0.8)`. Multi-frequency interference pattern.
- **Visualist**: Water surface caustics from `abs(waveX * waveY)`, chromatic dispersion scaled by crest intensity, HDR specular highlights (`pow(crest, 8.0)`), ACES tone mapping.
- **Interactivist**: Bass drives wave amplitude (`intensity * (1.0 + bass * 0.6)`), mouse creates wave sources via `mouseMask`, depth controls attenuation (`depthAtten = mix(1.0, 0.2, depth)`).
- **Optimizer**: Single depth sample, clamped chromatic offsets.

## Alpha Semantics
`clamp(intensity * 12.0 * interferenceIntensity * depth * 2.5, 0.15, 0.95)` — wave_amplitude × interference_intensity × depth.

## Key Changes
- New helpers: `acesToneMap`, `hash21`
- `depth-aware` feature added
- Line count: 79 → 123
- Naga: PASS
