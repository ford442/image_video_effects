# Visualist Notes: gen-hypnotic-vortex-tunnel

**Role:** Visualist  
**Upgraded:** 2026-07-13  
**Lines:** 139 → 198 (+59)

## Color Science & Lighting Upgrades

- **HDR > 1.0:** Layered tunnel colors, arc strobes, and rim light now sum to HDR values before tone mapping.
- **ACES tone mapping:** Unified to single canonical `acesToneMap` and applied after hue-preserving clamp.
- **Hue-preserving clamp:** Added `huePreservingClamp(col, 6.0)` before ACES.
- **OkLab mixing:** Blended previous-frame feedback with current tunnel colors in OkLab space for smooth, perceptual trails.
- **Blackbody temperature:** Fog/haze color driven by `blackbody()` so the tunnel depth shifts from warm near-field to cool far-field.
- **Fresnel rim lighting:** Added a rim term on the tunnel rings based on radial view angle, boosted by treble.
- **Atmospheric fog / volumetric glow:** Added exponential radial fog that thickens with bass and softens ring edges.

## Technical Changes

- Added `rgbToOkLab` / `okLabToRgb`, `blackbody`, `huePreservingClamp`, `valueNoise`, `fbm`, and `hash21` helpers.
- Replaced magic `6.2832` constants with `TAU` constant.
- Switched previous-frame read to `textureLoad(dataTextureC, coord, 0)`.
- Semantic alpha now includes fog contribution and luma.
- All three required outputs written every frame.

## JSON Update

- Added feature tags: `hdr-aces`, `oklab-mix`, `blackbody-temperature`, `fresnel-rim`, `atmospheric-fog`, `volumetric-glow`, `hue-preserving-clamp`.

## Validation

- `wgsl_precommit_gate.py` passed: naga OK, bindgroup compatible, workgroup size `(16, 16, 1)`.
