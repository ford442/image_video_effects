# gen-velocity-bloom — Kimi upgrade notes

## What changed
- Added `plasmaBuffer[0]` audio reads (bass/mids/treble) to drive bloom radius, intensity, and color temperature.
- Refreshed header to Standard Hybrid Header format with accurate Features list.
- Replaced simple Reinhard tone map with `acesToneMap` + `ign` dither.
- Switched final write to premultiplied alpha (`col*alpha, alpha`).

## Validation
- `naga public/shaders/gen-velocity-bloom.wgsl` → OK.
- No banned tokens (`textureSample(`, `outputTex`, etc.).
- Reads `plasmaBuffer[0]`.

## Suggested JSON updates
- Add `audio-reactive` to features.
- Keep existing params; no new tunables introduced.
