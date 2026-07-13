# Visualist Notes: gen-cycloid-bloom

**Role:** Visualist  
**Upgraded:** 2026-07-13  
**Lines:** 133 → 208 (+75)

## Color Science & Lighting Upgrades

- **HDR > 1.0:** Core blackbody glow and rim lighting push colors above 1.0 before ACES.
- **ACES tone mapping:** Kept canonical `acesToneMap`, applied after hue-preserving clamp.
- **Hue-preserving clamp:** Added `huePreservingClamp(col, 7.0)` before tone mapping.
- **OkLab mixing:** Converted accumulated bloom color to OkLab and blended with a warm blackbody tone driven by bass/mids.
- **Blackbody temperature:** Added a central core glow using `blackbody()` that blooms from the flower center.
- **Fresnel rim lighting:** Added edge rim on petals based on radial distance, boosted by treble.
- **Volumetric glow:** Added a soft glow layer proportional to accumulated petal brightness and mids energy.

## Technical Changes

- Added `rgbToOkLab` / `okLabToRgb`, `blackbody`, `huePreservingClamp`, `valueNoise`, and `fbm` helpers.
- Replaced the inner `if (di < minDist)` branch with a branchless `select`/`mix` update to satisfy branchless preference.
- Switched previous-frame read to `textureLoad(dataTextureC, coord, 0)`.
- Semantic alpha preserved as a function of color magnitude and bass.
- All three required outputs written every frame.

## JSON Update

- Added feature tags: `hdr-aces`, `oklab-mix`, `blackbody-core`, `fresnel-rim`, `volumetric-glow`, `hue-preserving-clamp`.

## Validation

- `wgsl_precommit_gate.py` passed: naga OK, bindgroup compatible, workgroup size `(16, 16, 1)`.
