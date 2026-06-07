# stipple-render v2 — Upgrade Notes

## Overview
Upgraded from ~88 lines to **129 lines**. Replaced simple noise stippling with weighted Voronoi-style stippling, ink bleeding, and cross-hatching.

## Algorithmist Changes
- Blue noise distribution via `blue_noise21()` for pleasing randomness
- Lloyd's relaxation approximation: cell centers offset by local luminance
- Dot size inversely proportional to luminance (darker = bigger dot)
- Grid-based Voronoi approximation using `floor(uv * resolution / cellScale)`

## Visualist Changes
- Paper texture via layered high-frequency noise
- Cross-hatching in dark regions using dual sine waves
- Ink-on-paper color palette (warm paper, dark ink)
- ACES tone mapping for ink richness
- Wet ink bleeding effect near mouse

## Interactivist Changes
- Bass drives stipple cell scale (audioScale = 1.0 + bass * 0.3)
- Mouse creates "wet ink" zone where dots bleed together (bleed factor up to 2.5×)
- Depth controls dot size perspective (depthScale = mix(0.6, 1.6, depth))

## Alpha Strategy
`alpha = clamp((dotMask + wetDot * 0.5 + hatchMask * 0.2) * inkSaturation * depth, 0.05, 1.0)`
- Semantic: dot density × ink saturation × depth
- Never hardcoded to 1.0

## Validation
- naga: ✅ PASSED
- workgroup_size: (16, 16, 1)
- Bindings: 13 exact canonical
