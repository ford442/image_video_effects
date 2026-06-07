# volumetric-god-rays v2 — Upgrade Notes

## Category
interactive-mouse (unchanged)

## Upgrade Summary
- **Workgroup size**: `(16, 16, 1)` unchanged
- **Line count**: 96 → ~132
- **Naga status**: PASS

## Algorithmist Changes
- Replaced simple radial glow accumulation with ray-marched volumetric lighting.
- Added Mie scattering phase function (Henyey-Greenstein approximation) per sample.
- Depth controls shaft occlusion (`depthOcclusion = mix(0.3, 1.0, srcDepth)`) and atmospheric extinction.
- Reduced samples from 64 → 48 to balance quality/performance with heavier per-sample math.

## Visualist Changes
- Added procedural dust particle scatter (hash-based noise) in light shafts.
- Added chromatic dispersion at shaft edges (R/G/B weighted differently along radial direction).
- Added ACES tone mapping.
- Added HDR bloom on light source (exponential falloff from mouse position).
- Added atmospheric haze tint driven by mids.

## Interactivist Changes
- Bass drives dust density (`dustDensity = density × (1.0 + bass × 0.8)`).
- Mouse positions the light source (unchanged behavior, preserved).
- Depth controls shaft occlusion and atmospheric extinction.

## Alpha Semantics
`alpha = clamp(scatteredLuma × exposure × 2.0 × dustDensity × extinction, 0.0, 1.0)`
- Encodes scattered light intensity, dust density, and depth attenuation.
- Never hardcoded to 1.0.

## Params (unchanged)
density, decay, weight, exposure

## Tags Added
atmosphere

## Feature Flags Added
depth-aware
