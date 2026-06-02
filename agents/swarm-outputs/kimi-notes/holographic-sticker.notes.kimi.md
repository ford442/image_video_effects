# holographic-sticker — Kimi Notes

## Changes Made
- Added temporal foil shimmer persistence via `dataTextureC` blend.
- Added chromatic view-angle dispersion (hue shifts per viewing angle + depth).
- Added audio-driven sticker pulse (bass expands radius).
- Fixed depth-layered + luminance-key alpha.

## Wow Factor
- Sticker pulses with bass for reactive holographic feel.
- Foil iridescence drifts organically with temporal shimmer.
- Viewing angle + depth drive hue for realistic holography.

## Risks for Claude Polish
- Audio pulse may make radius jump suddenly at high bass.
- Temporal blend factor (0.04 + mids*0.015) is very subtle.
- `dataTextureC` tint may accumulate toward a single hue over time.
