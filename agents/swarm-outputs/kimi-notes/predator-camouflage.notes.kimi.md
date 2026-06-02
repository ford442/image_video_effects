# predator-camouflage — Kimi Batch E Notes

## Changes Made
- Added audio-reactive cloak radius: bass scales cloak size via `bass_env()`
- Added audio-reactive chromatic aberration: bass expands R offset, treble shifts B offset
- Added temporal ghosting: previous frame bleeds through cloak boundary
- Added depth-aware refraction: depth scales distortion strength
- Added depth-aware edge glow: near objects get brighter edge highlight
- Added treble-driven shimmer sparkle intensity
- Replaced hardcoded alpha `1.0` with dynamic alpha from mask + shimmer + bass
- Added `dataTextureA` write for temporal persistence

## Wow Factor
- Cloak now pulses with the music — bass drops make it expand dramatically
- Temporal ghosting creates a genuine "phasing out" Predator effect

## Risks
- `dataTextureC` read for ghosting adds texture sample per pixel inside cloak
- Audio radius expansion may cause cloak to cover entire screen on heavy bass
