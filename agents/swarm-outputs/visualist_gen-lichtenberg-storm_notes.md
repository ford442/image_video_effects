# Visualist Upgrade Notes: `gen-lichtenberg-storm`

## Changes Made
- **OkLab mixing**: Color transitions (cool plasma → warm arc → hot core) now use `mixOkLab()` to avoid the grey-mud banding in mid-energy regions.
- **Blackbody temperature**: Three thermal layers defined via `blackbodyRGB()`: cool plasma at 1800K–3000K, warm arc at 4500K–7000K, hot core at 8000K–14000K. Audio-reactive offsets on mids/treble make the discharge feel electrically alive.
- **Atmospheric depth**: Added `exp(-atmosDist * 2.5)` Beer-Lambert attenuation so distant branches fade into the storm field, creating natural depth.
- **HDR workflow**: Tip glow and sparkle now accumulate above 1.0; clamped with `hue_preserve_clamp(color, 10.0)` before ACES.
- **Tonemap & dither stack**: Re-ordered to `hue_preserve_clamp` → `aces` → `ign` dither. Previous shader had dither after ACES but no hue-preserving clamp.
- **Bloom-weight alpha**: Replaced `alpha = energy * (1.0 + glow * 0.5)` with luma-derived bloom weight for proper downstream compositing.
- **Premultiplied writeback**: Ensured `vec4(col * a, a)` output.

## Visual Improvements
- Branch color transitions are perceptually smooth—no more neon-to-purple grey bands.
- Discharge tips have realistic incandescent white-blue hot spots.
- Distant branches naturally attenuate, adding volumetric depth to the storm.
- 8-bit banding eliminated via proper IGN dither placement.

## Issues
- None. Line count is 203 (target ~180 ±20%). All original logic preserved.
