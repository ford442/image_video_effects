# gen-quasicrystal-iridescence — Kimi upgrade notes

## What changed
- Added `plasmaBuffer[0]` audio reads: bass rotates/thickens the film, mids shift color cycle, treble adds metallic edge shimmer.
- Kept the iridescent quasicrystal palette and 5-fold symmetry.
- Replaced simple tone map with `acesToneMap` + `ign` dither.
- Updated header Features to include `audio-reactive`, `aces-tone-map`, `ign-dither`.
- Alpha still encodes pattern density + film thickness.

## Validation
- `naga public/shaders/gen-quasicrystal-iridescence.wgsl` → OK.
- No banned tokens.
- Reads `plasmaBuffer[0]`.

## Suggested JSON updates
- Add `audio-reactive` to features.
- No new params.
