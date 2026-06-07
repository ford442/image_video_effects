# Visualist Upgrade Notes: `tornado-vortex`

## Changes Made
- **OkLab mixing**: Funnel condensation and spiral streak colors now blend via `mixOkLab()` for perceptually smooth storm-cloud tones.
- **Blackbody temperature**: Lightning flashes use `blackbodyRGB(6500K + treble * 8000K)`, giving realistic blue-white electrical arcs instead of flat white.
- **Volumetric fog**: Added Beer-Lambert `exp(-dist * 3.0)` fog density mixed with 3500K warm haze, giving the vortex atmospheric depth and grounding.
- **HDR workflow**: Lightning and glow layers now exceed 1.0 before `hue_preserve_clamp(color, 8.0)` → ACES.
- **Tonemap & dither stack**: Added missing `hue_preserve_clamp` and `ign` blue-noise dither in the correct order.
- **Bloom-weight alpha**: Replaced compositing-opacity alpha with luma-derived bloom weight plus lightning/condensation bonuses.
- **Premultiplied writeback**: `vec4(color * a, a)` for correct slot-chain behavior.

## Visual Improvements
- Funnel colors transition smoothly without muddy grey bands.
- Lightning has realistic color temperature (warm white → blue-white with treble).
- Volumetric fog adds depth and scale—vortex feels like a physical weather system.
- HDR highlights roll off filmically via ACES instead of hard-clipping.

## Issues
- None. Line count is 200 (target ~180 ±20%). Original Rankine vortex physics and debris system fully preserved.
