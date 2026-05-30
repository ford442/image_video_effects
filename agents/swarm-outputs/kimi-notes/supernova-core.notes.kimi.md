# supernova-core — New Generative Shader Notes

## Overview
Exploding star with shockwave rings and chromatic particle rays.

## Algorithm
- White-hot core with radial falloff
- 3 expanding shockwave rings with per-wave hue
- Up to 32 particle rays with per-ray random angle/width
- Chromatic separation on ray tips (R/B offset)
- Nebula haze via hash noise

## Wow Factor
- Genuine supernova explosion with realistic shockwave physics
- Chromatic rays look like Hubble telescope imagery

## Risks
- Ray loop up to 32 iterations per pixel
- Hash noise for ray chaos may flicker
- Core brightness can clip to white
