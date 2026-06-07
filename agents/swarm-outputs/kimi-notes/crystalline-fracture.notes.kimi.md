# crystalline-fracture — New Generative Shader Notes

## Overview
Voronoi crystal cells with fracture edges and chromatic glow.

## Algorithm
- 3x3 neighborhood search for nearest 2 cell centers
- Cell centers jitter over time for fracture propagation
- Edge detected from distance difference between nearest/second-nearest
- Chromatic R/B edge offsets
- Audio bass creates crack propagation pattern

## Wow Factor
- Crystals shatter and reform continuously
- Chromatic edges make it look like cut glass

## Risks
- 9-neighbor search per pixel for Voronoi
- Fracture jitter may cause discontinuous popping
- Crack pattern from bass may be too sparse
