# gen-torus-knot-rainbow — Kimi Notes

## Changes Made
- Added chromatic tube gradient: warm inner (R-shifted hue) vs cool outer (B-shifted hue).
- Added audio-driven wind parameter modulation (`qWind += bass * 1.5`).
- Added depth output to `writeDepthTexture`.
- Added temporal persistence via `dataTextureC` blend for trail effect.

## Wow Factor
- Tube gradient gives the torus knot volumetric color temperature.
- Audio modulates winding topology in real-time for reactive geometry.
- Trails persist across frames for smoother motion.

## Risks for Claude Polish
- Audio-driven `qWind` may cause topology jumps at high bass; consider smoother LPF.
- `STEPS=300` is already expensive; chromatic blur adds 3x sample cost.
- Depth output based on `glowAcc` may not correlate with visual depth well.
