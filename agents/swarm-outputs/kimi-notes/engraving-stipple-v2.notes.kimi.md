# engraving-stipple v2 — Upgrade Notes

## Agent Synthesis
- **Algorithmist**: Added image-gradient-aware contour hatching (`gradDir` drives hatch direction), cross-hatching with density modulation based on `gradMag`, burr effect at line crossings via multiplied sine grids, stipple hash with pressure scaling.
- **Visualist**: Copperplate engraving aesthetic with ink pooling (`poolInk` at deep blacks), warm paper texture with procedural noise, ACES tone mapping, chromatic edge darkening on deep blacks (`deepBlack` shifted toward blue/cyan).
- **Interactivist**: Bass drives tool pressure (`pressure = 1.0 + audio.x * 0.5`) for deeper/darker lines; mouse acts as burin cutting tool (`burin` + `burinCut`); depth controls line width perspective (`lineWidth` scales with depth).
- **Optimizer**: Gradient computed with 4 samples reused for edge and direction; hatch lines branchlessly blended via `mix()`.

## Alpha Semantics
`finalAlpha = lineDensityAlpha * inkSat * depth + 0.06`
- Encodes line density, ink saturation, and depth-based perspective. Base 0.06 ensures paper texture remains visible.

## Line Count
~133 lines

## Naga Status
✅ Validation successful

## Bindings
Exact canonical 13-binding header used. No additions.

## Params
Unchanged: line_density, stipple_scale, contrast, light_rotation.
