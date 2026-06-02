# chronos-brush — Kimi Batch E Notes

## Changes Made
- Added chromatic brush tints: HSV hue cycles per click + time, bass shifts saturation
- Added audio boost to brush size and opacity via `bass_env()`
- Added depth-aware paint intensity: near surfaces paint more opaquely
- Temporal persistence via `dataTextureC` for freeze-frame accumulation
- Dynamic alpha from brush intensity + bass energy

## Wow Factor
- Each brush stroke is tinted with a unique prismatic color that evolves
- Audio makes the brush swell and pulse with the beat

## Risks
- HSV conversion inline adds ~10 instructions per pixel
- `clickCount` from `u.config.y` may not increment as expected depending on frontend
