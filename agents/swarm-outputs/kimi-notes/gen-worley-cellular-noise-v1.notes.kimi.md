# gen-worley-cellular-noise — Kimi Notes

## Shader Summary
Worley noise with F1 (nearest feature point), F2 (second nearest), and F2-F1 cell boundary detection. Feature points animate over time with bass-driven movement speed. Organic tissue palette with subsurface scattering simulation on boundaries. Combined with fBm for organic variation.

## Key Features
- 3x3 neighborhood search for feature points
- Time-varying feature point animation
- fBm overlay for organic texture variation
- Subsurface scattering glow on cell boundaries
- Mouse attracts feature point field
- Depth controls cell size perspective
- Temporal feedback for organic drift

## Parameters
- `zoom_params.x` — Cell scale (3-12 grid density)
- `zoom_params.y` — Animation speed
- `zoom_params.z` — Chromatic aberration amount
- `zoom_params.w` — Organic variation (fBm mix)

## Alpha Semantics
`alpha = scatter * tissue_density * depthSample`
Represents boundary proximity times tissue density times depth awareness.

## Naga Status
PASS — naga validation successful.
