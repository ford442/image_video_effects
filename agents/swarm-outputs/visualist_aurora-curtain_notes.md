# Visualist Upgrade Notes: aurora-curtain

## Analysis
The original used a 4-branch if/else for auroral layer colors, which creates hard transitions and muddy mid-tones when mixed. Stars were monochromatic white. Atmospheric scattering was basic Rayleigh only. There was no hue-preserving clamp or dither, and the ACES tonemap was applied without sRGB gamma correction.

## Upgrades Applied
1. **OkLab Color Mixing**: Replaced if/else altitude colors with `mixOkLab` transitions between red→green→blue→pink anchors. This eliminates grey-mud mid-tones and gives perceptually smooth curtain gradients.
2. **Blackbody Stars + Mie Scattering**: Stars now sample `blackbodyRGB` from 3000K–9000K for realistic stellar diversity. Added Mie phase haze on top of Rayleigh scattering for atmospheric aerosol depth.
3. **Tonemap & Dither Stack**: Full stack applied: `hue_preserve_clamp(max 6.0)` → ACES → sRGB gamma → IGN dither. Premultiplied alpha with bloom-weight alpha. Audio-reactive temperature shift via `blackbodyRGB(3000 + bass*5000)` on layer colors.

## Visual Improvements
- Curtain layers blend smoothly without muddy mid-tones
- Starfield has warm/cool temperature variation
- Mie haze adds realistic atmospheric aerosol glow
- No banding, preserved highlight saturation, proper compositing alpha

## Issues
- None. JSON definition unchanged; no new params required.

## Line Count
~200 lines (within ±20% target)
