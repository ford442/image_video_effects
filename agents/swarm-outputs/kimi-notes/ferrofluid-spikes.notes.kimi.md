# ferrofluid-spikes — New Shader Notes

## Overview
Mouse-driven ferrofluid simulation using fbm noise fields and magnetic attraction.

## Algorithm
- Mouse position creates magnetic field (smoothstep falloff)
- 4-octave fbm generates base liquid surface
- 3-octave fbm creates spike height map
- Specular highlights calculated from normalized noise gradient
- Audio adds turbulent noise to surface

## Wow Factor
- Dark liquid surface literally grows metallic spikes toward the cursor
- Audio turbulence makes spikes dance and quiver

## Risks
- 7 fbm evaluations per pixel (4 + 3 octaves)
- Specular lighting is approximate (noise-based normal)
- No temporal feedback — purely procedural each frame
