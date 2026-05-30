# kaleido-scope v2 Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Replaced simple angular mirroring with Poincaré-disk-inspired hyperbolic compression (`hypR = r / (1 - min(r*0.94, 0.99))`). Added animated morphing between tessellation types A/B driven by bass-accelerated sine.
- **Visualist**: Iridescent metallic fills on tile boundaries using cosine hue triplet. HDR specular highlights at ring-vertex intersections. ACES tone mapping on final composite. Chromatic aberration at sector edges via depth-driven RGB separation.
- **Interactivist**: Bass accelerates tessellation morph speed. Mouse warps disk center with `lensDistort()` creating lens-like barrel distortion. Depth adds stereoscopic RGB channel separation (`sep = 0.004 + depth*0.014`).
- **Optimizer**: Kept `@workgroup_size(16,16,1)`. Used early-out bounds check. Branchless `smoothstep` for boundaries.

## Alpha Semantic
`alpha = clamp(boundary * 0.5 + depth * 0.25 + vertex * 0.18 + bass * 0.06, 0.1, 0.92)`
- Tile boundary strength × depth factor. Never opaque 1.0.

## Lines
~138 WGSL lines

## Changes
- New helpers: `acesToneMap`, `hash22`, `lensDistort`, `poincareMap`
- Added chromatic aberration via per-channel UV offsets
- Added metallic/iridescent boundary tint and specular vertex highlights
- JSON description updated; tags expanded
