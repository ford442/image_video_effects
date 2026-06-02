# holographic-flicker — Kimi Batch E Notes

## Changes Made
- Added temporal ghosting: previous frame offset creates RGB channel ghosts
- Added depth-rainbow: hue shifts with depth + bass
- Added audio-reactive flicker: bass drives blackout, treble drives micro-glitch
- Added chromatic ghosting: R/B channels sample from different temporal offsets
- Hologram intensity scales with audio

## Wow Factor
- Ghosting creates genuine volumetric depth illusion
- Audio blackouts make the hologram stutter like a failing projector

## Risks
- `dataTextureC` reads for ghosting add 2 extra texture samples per pixel
- Blackout probability (`bass * 0.2`) may be too frequent on bass-heavy tracks
