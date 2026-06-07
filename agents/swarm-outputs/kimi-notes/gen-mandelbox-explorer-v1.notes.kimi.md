# gen-mandelbox-explorer — New Shader Notes

## Overview
2D cross-section of the 3D Mandelbox fractal, rendered with orbit-trap metallic coloring, ambient occlusion, and HDR specular highlights.

## Algorithm
- Box fold: clamp each coordinate to [-1,1] then reflect
- Sphere fold: scale up if |z|<0.5, invert if 0.5<|z|<1.0
- Iterate z = scale * sphereFold(boxFold(z)) + c for 30–90 steps
- Track minimum orbit distance for ambient occlusion proxy
- Metallic palette: gold/steel mix modulated by AO
- HDR specular from exp(-orbitMin^2 * 12)
- Chromatic edge dispersion on high-AO (interior) regions
- ACES filmic tone mapping

## Interactivity
- Mouse X rotates the 2D cross-section plane
- Bass modulates the Mandelbox scale parameter (-2.5 to 2.5)
- Param1 controls scale
- Param2 controls iteration depth
- Param3 controls slice thickness (z-offset of cross-section)
- Param4 controls specular highlight intensity

## Alpha Semantics
alpha = orbit_density × surface_confidence × depth
- High on dense metallic surfaces, low in empty space

## Wow Factor
- Gorgeous metallic Mandelbox interior with gold and steel tones
- Mouse-driven plane rotation reveals hidden 3D structure
- Bass-driven scale inversion creates dramatic shape changes

## Risks
- Generative — no image input
- High iteration counts may impact low-end GPUs
- Negative scale values can produce inverted/exploded shapes
