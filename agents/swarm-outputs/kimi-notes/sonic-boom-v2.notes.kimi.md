# sonic-boom v2 Upgrade Notes

## Changes
- Added Mach cone geometry with `asin(1/Mach)` angle calculation
- Added Prandtl-Glauert-inspired compressible flow singularity (`coneDist`)
- Added shock diamond patterns (Mach diamonds) via `diamondPhase`
- Added condensation cloud physics with atmospheric density from depth
- Added volumetric fog scatter on condensation regions
- Added HDR bloom on shock fronts
- Added ACES tone mapping
- Added chromatic aberration scaled by velocity magnitude
- Bass drives Mach number (subsonic→transonic→supersonic)
- Mouse controls flight path center
- Depth controls atmospheric density (affects shock visibility)

## Alpha Semantics
`alpha = shock_intensity * condensation_density * depth * velocity_term`
- Shock intensity from ring sum + Mach diamonds + shock front
- Condensation density from Gaussian falloff of cone distance
- Depth from readDepthTexture for atmospheric density

## Params
1. Ring Radius — shock cone base radius
2. Ring Width — shock front thickness
3. Distortion — Mach number / strength
4. Chrom. Split — chromatic aberration amount

## Line Count
~146 lines
