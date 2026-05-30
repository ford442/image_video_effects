# iso-hills v2 Upgrade Notes

## Overview
Upgraded from ~78 lines to 169 lines. Category: artistic.

## Algorithmist Changes
- Replaced simple iso-lines with analytic derivative-based contour extraction.
- Added 5-octave fBm terrain generation (`fbm()` + `noise()` + `hash21()`).
- Simulated hydraulic erosion via bass-triggered rainfall and low-frequency river channels.
- Mouse water drops and ripple array carve channels dynamically.

## Visualist Changes
- Elevation-based palette: valley (green) → meadow → rock (brown) → snow (white).
- Added contour hachures for topographic map aesthetic.
- HDR snow sparkle highlights using `pow(shade, 4.0)`.
- ACES tone mapping on final output.
- Depth-based atmospheric haze on distant hills.

## Interactivist Changes
- `ripples` array creates wave-carved channels.
- Mouse position carves local terrain when mouse is down.
- Bass triggers rainfall/erosion events.
- Depth texture controls haze intensity.

## Alpha Strategy
`alpha = contour * elevation_confidence * (1.0 - haze) + height * 0.12 + bass * 0.04`

## Params Mapping
- steps (x) → contourSteps (4–32)
- height_scale (y) → heightScale (*2.0)
- smoothness (z) → terrain smoothing + ripple carve strength
- shadow_strength (w) → hazeStrength (0–0.45 atmospheric haze)

## Validation
- naga: PASSED
- workgroup_size: (16, 16, 1)
