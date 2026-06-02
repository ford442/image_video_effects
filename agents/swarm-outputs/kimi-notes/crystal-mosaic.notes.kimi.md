# crystal-mosaic — New Shader Notes

## Overview
Triangular mosaic tile effect with rotation, chromatic edges, and depth parallax.

## Algorithm
- Screen divided into staggered triangular grid
- Each tile rotates based on mouse proximity + audio bass
- Depth shifts tile UV for parallax effect
- Chromatic aberration at tile edges (R/B sampled at offset)
- Mids add purple border highlights

## Wow Factor
- Image shatters into prismatic crystal shards
- Mouse movement sends ripples of rotation through tiles

## Risks
- Triangular cell math is approximate (using rhombus subdivision)
- Chromatic offset may be subtle at low zoom_params.z values
- No anti-aliasing on tile edges
