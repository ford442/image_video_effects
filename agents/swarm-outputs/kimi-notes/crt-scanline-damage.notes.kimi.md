# crt-scanline-damage — Kimi Notes

## Changes Made
- Added `writeDepthTexture` passthrough (was missing in original).
- Added temporal phosphor decay via `dataTextureC` blend (`prev * 0.85`).
- Added chromatic barrel separation (R/B channel offset by depth).
- Added audio-driven RGB separation (`sep *= (1 + bass * 0.4)`).

## Wow Factor
- Phosphor decay gives authentic CRT persistence ghosting.
- Depth-aware barrel distortion varies per-pixel for 3D CRT feel.
- Bass pumps RGB separation for reactive glitch intensity.

## Risks for Claude Polish
- Depth write was missing entirely; now added but may need depth-aware values.
- Phosphor decay blend (0.06 + mids*0.02) is subtle; consider increasing for visibility.
- Vertical roll trigger uses `hash11(floor(time*2)) < 0.05`; may be too infrequent.
