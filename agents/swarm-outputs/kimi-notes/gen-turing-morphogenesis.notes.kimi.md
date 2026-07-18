# gen-turing-morphogenesis.wgsl upgrade notes

## Changes
- Added missing helpers `ign` and `huePreserveClamp` after existing `acesToneMap`.
- Added audio band reads: `mids = plasmaBuffer[0].y`, `treble = plasmaBuffer[0].z`.
- Enhanced audio reactivity:
  - bass → feed/kill modulation and persistence (existing).
  - mids → organic palette color-shift offset.
  - treble → fine blue-white sparkle on high-curvature regions.
- Replaced final `acesToneMap(color * 1.2)` with `acesToneMap(huePreserveClamp(color, 2.0))` + `ign` dither + clamp.
- Converted final `textureStore` to premultiplied alpha.
- Updated header Features comment to include `ign-dither` and `premultiplied-alpha`.

## Validation
`/root/.cargo/bin/naga public/shaders/gen-turing-morphogenesis.wgsl` → OK

## JSON updates
`shader_definitions/generative/gen-turing-morphogenesis.json` features array now includes:
`audio-reactive`, `aces-tone-map`, `ign-dither`, `premultiplied-alpha`.

## Lines after change
166
