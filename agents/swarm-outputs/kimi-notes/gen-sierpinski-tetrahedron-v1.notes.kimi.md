# gen-sierpinski-tetrahedron — Kimi Notes

## Shader Summary
Sierpinski tetrahedron rendered as 2D projection with orbit trap coloring. Uses iterated contraction toward nearest vertex of the 4 tetrahedron vertices. Jewel-tone palette (emerald, sapphire, ruby, amethyst) with metallic surface sheen and HDR specular highlights on depth edges.

## Key Features
- 4-vertex tetrahedron IFS with orbit trap tracking
- 3D rotation with mouse control or auto-rotation
- Perspective projection with depth-aware scaling
- Jewel-tone palette indexed by closest vertex
- Chromatic aberration on depth edges
- Temporal feedback smooths orbit trap values

## Parameters
- `zoom_params.x` — Recursion depth (4-10 iterations)
- `zoom_params.y` — Rotation speed
- `zoom_params.z` — Perspective strength
- `zoom_params.w` — Chromatic aberration amount

## Alpha Semantics
`alpha = surface_density * (recursion_level/10) * depthFactor`
Represents surface density modulated by recursion depth and depth awareness.

## Naga Status
PASS — naga validation successful.
