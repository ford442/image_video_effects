# tornado-vortex — New Generative Shader Notes

## Overview
Spiral tornado funnel with debris and lightning.

## Algorithm
- Funnel shape: radius increases with height (y)
- Spiral pattern from angle * 6 + y * 20 - time * spin
- 20 debris particles in golden-spiral arrangement
- Lightning: random flashes with angular streak pattern
- Ground dust at bottom

## Wow Factor
- Debris particles spiral realistically up the funnel
- Lightning flashes are genuinely startling

## Risks
- Debris loop: 20 particles per pixel
- Lightning flash probability may be too low
- Funnel shape fixed to center — no mouse control
