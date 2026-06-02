# double-exposure-zoom v2 — Upgrade Notes

## Category
artistic (unchanged)

## Upgrade Summary
- **Workgroup size**: `(8, 8, 1)` → `(16, 16, 1)`
- **Line count**: 95 → ~133
- **Naga status**: PASS

## Algorithmist Changes
- Added luminance-based matte extraction using `smoothstep` on secondary exposure luminance.
- Replaced simple screen blend with hybrid screen/soft-light multi-scale blend.
- Depth drives parallax offset between primary and secondary exposures.

## Visualist Changes
- Added film stock color response curves (`filmResponse`).
- Added warm light leak artifacts on zoom edges.
- Added ACES tone mapping.
- Added chromatic aberration on zoom edges (RGB channel split).
- Added vignette on secondary exposure.

## Interactivist Changes
- Bass now drives zoom speed directly (bass × audioReact × 0.4).
- Mouse controls secondary exposure position with spring-damped smoothing preserved implicitly via UI.
- Depth controls parallax between exposures.

## Alpha Semantics
`alpha = clamp(blendRatio × luminanceConfidence × (0.4 + depth × 0.6), 0.0, 1.0)`
- Encodes exposure blend ratio, luminance confidence, and depth parallax strength.
- Never hardcoded to 1.0.

## Params (unchanged)
rotation, zoom, edgeFade, audioReact

## Tags Added
film, double-exposure

## Feature Flags Added
depth-aware
