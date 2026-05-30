# pixelate-blast v2 Upgrade Notes

## Agent Perspectives

### Algorithmist
- Replaced uniform grid blocks with animated Voronoi cells
- Added `voronoi()` returning distance to nearest neighbor, second-nearest, and cell hash
- Domain warping via `domainWarp()` perturbs cell field for organic movement
- Cell sizes animated by time-driven offset vectors per cell

### Visualist
- Cell-edge glow: cyan/blue glow on Voronoi boundaries
- Internal gradient shading: brightness falls toward cell edges
- Chromatic aberration on blast radius: R/B channels sampled with offset
- Vignette darkens outer regions

### Interactivist
- Bass triggers radial blast waves via `sin(dist * 20 - time * 5) * bass`
- Mouse click spawns blast center via `ripples` array (existing infrastructure)
- Depth controls cell perspective via depth fade factor
- Cell density and edge glow are parameter-driven

### Optimizer
- 3x3 Voronoi neighborhood search (9 cells)
- Single-pass compute with canonical 13 bindings
- `@workgroup_size(16, 16, 1)`
- Reuse of `hash12` for both scalar and vector hashing

## Alpha Semantics
`alpha = clamp((blastEnergy * 0.5 + blastFade * 0.3) * centrality * depthFade + baseAlpha * 0.3, 0.0, 1.0)`
- Blast energy and radial fade weighted by cell centrality (brighter in cell centers)
- Depth fade modulates overall intensity

## Files Modified
- `public/shaders/pixelate-blast.wgsl` (~137 lines)
- `shader_definitions/retro-glitch/pixelate-blast.json` (category updated to distortion)

## Line Count
~137 WGSL lines (target: 130-150)
