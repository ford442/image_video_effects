# edge-glow-mouse v2 Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Added 5-tap unsharp masking kernel for edge enhancement, replaced simple glow with 4-octave anisotropic diffusion along edge tangents.
- **Visualist**: Neon HDR bloom with chromatic aberration on glow halos, ACES tone mapping, per-pixel film grain.
- **Interactivist**: Bass drives glow radius oscillation via `glowRadius * (1.0 + bass * 0.35)`, mouse creates local edge emphasis with `mouseAura`, depth controls glow falloff via `mix(1.0, 0.3, depth)`.
- **Optimizer**: Reduced redundant texture samples by reusing `baseColor`, loop unrolling friendly anisotropic gather.

## Alpha Semantics
`clamp(glowMask * glowRadius * depth * 2.5, 0.15, 0.95)` — edge_strength × glow_radius × depth.

## Key Changes
- New helpers: `acesToneMap`, `hash21`
- `depth-aware` feature added
- Line count: 78 → 136
- Naga: PASS
