# sketch-reveal v2 Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Cross-hatching density now follows image gradients via `atan2(edgeY, edgeX)`. Two perpendicular hatch layers modulated by luminance.
- **Visualist**: Graphite sheen (`0.92 + 0.08 * sin(...)`) on pencil strokes, paper tooth texture via `hash21`, chromatic edge darkening, ACES tone mapping.
- **Interactivist**: Bass drives reveal progression (`reveal * (1.0 + bass * 0.4)`), mouse acts as pencil adding smudge-offset strokes, depth controls stroke size perspective (`depthStrokeScale = mix(1.0, 0.4, depth)`).
- **Optimizer**: Single `sampleLuma` pattern reused for gradients, clamped UVs prevent out-of-bounds.

## Alpha Semantics
`clamp(revealProgress * strokeDensity * depth * 3.0, 0.12, 0.92)` — reveal_progress × stroke_density × depth.

## Key Changes
- New helpers: `acesToneMap`, `hash21`
- `depth-aware` feature added
- Line count: 80 → 132
- Naga: PASS
