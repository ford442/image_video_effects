# sand-dunes — New Generative Shader Notes

## Overview
Procedural desert landscape with wind-driven dune shifting.

## Algorithm
- 3 sine waves at different frequencies create dune heightfield
- Slope-derived shadow mask for 3D relief
- Wind streaks via high-frequency sine
- Audio bass creates ripple interference patterns
- Hash-based wind-blown particles

## Wow Factor
- Surprisingly realistic desert landscape from pure math
- Wind ripples and particles add life

## Risks
- Pure sine dune shapes may look artificial
- Shadow threshold hardcoded at slope=0, may need tuning
- Particles are sparse (threshold 0.995)
