# luma-glass v2 Upgrade Notes

## Changes
- Added physically-based refraction with Sellmeier-style dispersion (7-sample spectral loop)
- Luma-bright areas become high-index glass (`nGlass = 1.45 + luma * 0.35`), dark areas approach air
- Added caustic ray tracing approximation via light-direction dot power
- Added Fresnel reflections with view-dependent falloff
- Added chromatic dispersion (7 wavelengths, 400-650nm)
- Added subsurface scattering (`sss`) on thick glass
- Added ACES tone mapping
- Bass drives refractive index modulation
- Mouse deforms the glass surface via `mouseDeform`
- Depth controls glass thickness for refraction magnitude

## Alpha Semantics
`alpha = glass_thickness * fresnel_reflection * depth * attenuation`
- Glass thickness from depth × refraction parameter
- Fresnel reflection from view-normal dot product
- Depth from readDepthTexture for thickness scaling

## Params
1. Refraction Depth — base refraction strength
2. Surface Smoothness — normal map sensitivity
3. Specular Shine — specular power
4. Light Distance — light source Z offset

## Line Count
~147 lines
