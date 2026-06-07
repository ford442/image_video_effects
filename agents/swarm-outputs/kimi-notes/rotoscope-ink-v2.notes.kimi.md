# rotoscope-ink v2 — Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Added motion-aware rotoscoping via temporal edge detection (`temporalNoise` + animated hash simulates motion vectors), brushstroke-like tapered lines following `edgeDir` with sinusoidal width modulation, bleed edges for paint-bucket fill realism.
- **Visualist**: Hand-inked cel animation aesthetic with posterized fills, paint bleed at edges (`bleedEdge`), ACES tone mapping, procedural film grain, chromatic separation on fast-moving edges (R/B channel offset by `fastEdge`).
- **Interactivist**: Bass drives outline jitter (`jitter = hash12(...) * audio.x * 0.035`); mouse paints additional ink strokes (`mouseInk`); depth controls parallax between ink layers (`parallax` offset on `parallaxUV`).
- **Optimizer**: Edge gradient computed once and reused for magnitude, direction, and motion strength; chromatic samples only taken when `fastEdge > 0`.

## Alpha Semantics
`finalAlpha = outlineConfidence * motionStrength * depth + src.a * 0.12 + bleedEdge * 0.15`
- Encodes outline confidence, motion strength, and depth parallax. Source alpha and bleed edge add fill visibility.

## Line Count
~144 lines

## Naga Status
✅ Validation successful

## Bindings
Exact canonical 13-binding header used. No additions.

## Params
Unchanged: edge_threshold, posterize_levels, ink_density, shade_mix.
