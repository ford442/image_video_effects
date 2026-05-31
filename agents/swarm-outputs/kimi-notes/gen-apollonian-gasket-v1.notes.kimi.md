# gen-apollonian-gasket — New Shader Notes

## Overview
Apollonian gasket circle packing fractal rendered through iterative circle inversion geometry. Metallic circles with rainbow chromatic aberration and mouse-driven point inversion.

## Algorithm
- Five base circles in Descartes configuration (3 outer + 1 inner Soddy + 1 gap filler)
- For each pixel, repeatedly invert through the containing circle
- Inversion count tracked for coloring depth
- After inversion, compute distance to nearest circle boundary
- Color derived from inversion count (hue shift) and boundary distance (saturation/value)
- Mouse click inverts through a circle centered at mouse position
- Chromatic aberration on high-density (near-boundary) regions
- ACES filmic tone mapping

## Interactivity
- Bass drives recursion depth (3–10 inversion iterations)
- Mouse click inverts circles through a chosen point (circle inversion centered at cursor)
- Param1 controls recursion depth
- Param2 controls inversion circle size for mouse interaction
- Param3 controls overall circle size / zoom
- Param4 controls rainbow chromatic aberration intensity

## Alpha Semantics
alpha = circle_density × inversion_intensity × depth
- Higher near circle boundaries and after many inversions

## Wow Factor
- Classic Apollonian gasket with rich metallic coloring
- Iterative inversion reveals infinite recursive detail
- Mouse inversion creates dramatic geometric warping
- Bass-driven depth animates the recursive structure

## Risks
- Generative — no image input
- Circle configuration is approximate (not exact Descartes solution)
- High iteration counts (10) with inner loops may stress low-end GPUs
- Mouse inversion circle size needs tuning for good UX
