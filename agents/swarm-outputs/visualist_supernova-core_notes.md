# Visualist Upgrade Notes: supernova-core

## Analysis
The original shader used hand-mixed RGB approximations for blackbody cooling and lacked proper HDR handling. Shockwave colors were static lerps rather than physically grounded temperatures. There was no dithering, no hue-preserving clamp, and alpha was computed post-tone-map which loses HDR bloom information.

## Upgrades Applied
1. **Blackbody Radiation**: Replaced all static RGB cooling sequences with `blackbodyRGB(T)` using realistic temperatures (30000K core → 15000K → 2500K shockwaves). This gives physically accurate stellar colors.
2. **Volumetric Fog (Beer-Lambert)**: Added `exp(-density * dist)` ejecta fog that attenuates rays and re-emits scattered blackbody light, giving the supernova a sense of dusty depth.
3. **Tonemap & Dither Stack**: Added `hue_preserve_clamp` (max 8.0) before ACES filmic tonemap, then IGN blue-noise dither and sRGB gamma. All writes are premultiplied alpha with bloom-weight alpha.

## Visual Improvements
- Core and shockwave rings now have realistic stellar color temperature gradients
- Volumetric fog adds atmospheric depth and dusty nebula feel
- HDR highlights are preserved through hue-aware clamping, then smoothly filmic-mapped
- No 8-bit banding thanks to IGN dither

## Issues
- None. Shader remains within performance bounds (same loop counts, minimal added texture samples).

## Line Count
~190 lines (within ±20% target)
