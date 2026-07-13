# Visualist Notes: gen-solar-wind-ribbons

**Role:** Visualist  
**Upgraded:** 2026-07-13  
**Lines:** 142 → 192 (+50)

## Color Science & Lighting Upgrades

- **HDR > 1.0:** Ribbon edges, blackbody plasma flashes, and rim light produce HDR values before tone mapping.
- **ACES tone mapping:** Kept canonical `acesToneMap`, applied after hue-preserving clamp.
- **Hue-preserving clamp:** Added `huePreservingClamp(col, 6.0)` before ACES.
- **OkLab mixing:** Blended previous feedback frame with current ribbon render in OkLab for smooth temporal color trails.
- **Blackbody temperature:** Ribbon edge flashes and rim light use `blackbody()` for solar-corona color temperature.
- **Fresnel rim lighting:** Added a radial Fresnel rim that simulates glowing plasma limb around the curtain edges.
- **Atmospheric fog / volumetric glow:** Added radial fog and a cool background haze that deepens the solar-wind space.

## Technical Changes

- Added `rgbToOkLab` / `okLabToRgb`, `blackbody`, `huePreservingClamp`, `valueNoise`, and `fbm` helpers.
- Replaced magic `6.2832` and `3.14159` constants with `TAU` and `PI`.
- Switched previous-frame read to `textureLoad(dataTextureC, coord, 0)`.
- Semantic alpha now includes luma, streaks, and fog density.
- All three required outputs written every frame.

## JSON Update

- Added feature tags: `hdr-aces`, `oklab-mix`, `blackbody-plasma`, `fresnel-rim`, `atmospheric-fog`, `volumetric-glow`, `hue-preserving-clamp`.

## Validation

- `wgsl_precommit_gate.py` passed: naga OK, bindgroup compatible, workgroup size `(16, 16, 1)`.
