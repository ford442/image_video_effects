# gen-fireworks-strobe-shell — Kimi upgrade notes

## What changed
- Added full Standard Hybrid Header with Category `generative` and Features `audio-reactive, mouse-driven, fireworks, temporal, strobe, aces-tone-map, ign-dither, premultiplied-alpha`.
- Enhanced audio reactivity: `strobePulse` now responds to bass + mids; treble adds sparkle count.
- Added `ign` dither after ACES.
- Switched final write to premultiplied alpha.

## Validation
- `naga public/shaders/gen-fireworks-strobe-shell.wgsl` → OK.
- No banned tokens.
- Reads `plasmaBuffer[0]`.

## Suggested JSON updates
- Add `strobe` tag if not present.
- Ensure `features` includes `audio-reactive`.
