# coral-growth — New Generative Shader Notes

## Overview
Procedural coral branching using cell-based generation with animated growth.

## Algorithm
- Screen divided into cells
- Each cell contains 2-5 branch origins
- Branches grow along random direction with sub-branching
- Growth animated via fract(time * speed)
- Sub-branches fork at 50% length

## Wow Factor
- Coral literally grows before your eyes
- Each cell generates unique branching patterns

## Risks
- Branch loop up to 5 iterations per cell
- Line distance calculation per branch segment
- Growth animation resets abruptly (fract-based)
