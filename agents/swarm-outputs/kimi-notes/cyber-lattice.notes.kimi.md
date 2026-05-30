# cyber-lattice — Kimi Batch B Notes

## What I Changed
- Transformed flat 2D grid into a 3D perspective grid with vanishing point controlled by mouse position.
- Added thin-film interference colors (`thinFilm` function) producing cyan/gold/magenta iridescence on grid lines.
- Audio bass now warps grid lines via a sine wind field (`sin(gridP.y * 0.5 + time * 3.0 + bass * 4.0)`).
- Mouse click spawns a traveling geometric shockwave that inverts interference colors at the wavefront.
- Depth adds parallax offset to the vanishing point.

## What I'm Proud Of
When bass hits, the grid lines visibly bend and wave like reeds in wind, then snap back on the beat. The click shockwave inverting the interference colors is a genuine "I've never seen that before" moment.

## What Might Need a Human Eye
- The perspective projection uses `1.0 / zDepth` which can explode if the mouse is exactly at the pixel position (div by near-zero). The `+ 0.1` bias helps but verify edge behavior.
- `thinFilm` is a simplified 1-D approximation — it looks good but isn't physically accurate.
