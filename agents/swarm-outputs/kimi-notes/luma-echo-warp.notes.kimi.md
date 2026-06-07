# luma-echo-warp — Kimi Upgrade Notes

## Changes
- Added temporal echo feedback via `dataTextureC` with decay-based mixing
- Bass drives warp amplitude via `bass_env()` multiplier
- Depth parallax attenuation: deeper pixels warp less
- Treble adds sparkle to high-luma regions near mouse
- Curl-warped flow direction for organic displacement

## Wow Factor
- Temporal persistence creates liquid-memory trails that follow the mouse
- Bass pulses make the echo breathe in sync with music

## Risks
- `dataTextureC` dependency requires temporal slot chaining
- Echo decay may accumulate if not cleared between shader switches
