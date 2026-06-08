# Visualist Upgrade Notes: sand-dunes

## Analysis
The original had a static RGB desert palette with linear mixes that produce muddy ochre-to-umber transitions. Lighting was flat ambient with no directionality. Atmospheric haze was a simple lerp rather than physical extinction. No dither, no hue clamp, and tone mapping was applied without sRGB gamma.

## Upgrades Applied
1. **OkLab Palette + 3-Point Studio Lighting**: Desert colors now mix in OkLab for smooth perceptual gradients. Added key sun (`blackbodyRGB(4500+bass*2500)`), fill sky (`8000K`), and rim backlight (`6000K`) with approximate normals from slope. This gives sculpted dune form with warm/cool temperature contrast.
2. **Beer-Lambert Haze**: Replaced simple haze lerp with `exp(-density*dist)` transmittance and sky in-scatter, giving physically grounded aerial perspective tied to depth.
3. **Tonemap & Dither Stack**: `hue_preserve_clamp(max 5.0)` → ACES → sRGB gamma → IGN dither. Premultiplied alpha with bloom-weight alpha encoding sand density × wind exposure × transmittance.

## Visual Improvements
- Dunes look sculpted with directional warm sunlight and cool fill
- OkLab mixing eliminates muddy mid-tone transitions
- Beer-Lambert haze gives realistic depth-based atmospheric extinction
- Sparkles and subsurface scattering preserved through proper HDR stack

## Issues
- None. JSON definition unchanged.

## Line Count
~215 lines (within ±20% target)
