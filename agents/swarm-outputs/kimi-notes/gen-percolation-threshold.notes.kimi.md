# gen-percolation-threshold.wgsl upgrade notes

## Changes
- Added missing helpers `ign` and `huePreserveClamp` after existing `acesToneMap`.
- Added audio band reads: `mids = plasmaBuffer[0].y`, `treble = plasmaBuffer[0].z`.
- Enhanced audio reactivity:
  - bass → bloom amount pulse and threshold shift (existing threshold kept).
  - mids → cluster hue rotation shift.
  - treble → edge sparkle on cluster boundaries.
- Replaced final `acesToneMap(color * 1.1)` with `acesToneMap(huePreserveClamp(color, 2.0))` + `ign` dither + clamp.
- Converted final `textureStore` to premultiplied alpha.
- Updated header Features comment to include `ign-dither` and `premultiplied-alpha`.

## Validation
`/root/.cargo/bin/naga public/shaders/gen-percolation-threshold.wgsl` → OK

## JSON updates
`shader_definitions/generative/gen-percolation-threshold.json` features array now includes:
`audio-reactive`, `aces-tone-map`, `ign-dither`, `premultiplied-alpha`.

## Lines after change
162
