# rainbow-cloud v2 Upgrade Notes

## Summary
Upgraded from 96 lines to ~135 lines. Replaced simple 2D color blobs with ray-marched volumetric cloud using 3D Perlin noise, Mie scattering, iridescent nacreous colors, HDR god rays, ACES tone mapping, and atmospheric perspective.

## Algorithmist Changes
- Added 3D hash noise and 3D fbm for volumetric density field.
- Ray marching: 10 steps through z-slices per pixel.
- Mie scattering phase function `(1 + cos^2)/2` for forward-peaked light.
- Exponential light attenuation through cloud density.
- Density thresholding with soft edges.

## Visualist Changes
- Iridescent cloud colors (nacreous / polar stratospheric) shift hue by density and depth.
- HDR god rays through cloud gaps (high Mie phase + low density).
- ACES tone mapping for cinematic color.
- Atmospheric perspective fog based on depth.
- Source image visible through cloud transmittance.

## Interactivist Changes
- Bass drives cloud turbulence (`turbulence = 1.0 + bass * 0.6`).
- Mouse scatters cloud particles near cursor (`mouseScatter`).
- Depth controls density layering (`density *= depthFactor`).

## Alpha Semantics
`alpha = cloudDensity * iridescence * depthFactor`
- Clear sky or zero density = transparent.
- Dense iridescent cloud at foreground depth = opaque.

## Parameter Mapping
| Slot | Param | Range | Default |
|------|-------|-------|---------|
| x | Cloud Scale | 0-1 | 0.4 |
| y | Drift Speed | 0-1 | 0.35 |
| z | Density | 0-1 | 0.5 |
| w | Iridescence | 0-1 | 0.55 |

## Validation
- naga: OK
- Category: artistic (unchanged)
- readTexture: sampled (artistic overlay shader)
