# gen-belousov-zhabotinsky.wgsl upgrade notes

## Changes
- Renamed existing `acesToneMapping` helper to standard `acesToneMap`; `ign` and `huePreserveClamp` already present.
- Added audio band reads: `mids = plasmaBuffer[0].y`, `treble = plasmaBuffer[0].z`.
- Enhanced audio reactivity:
  - bass → feed-rate boost (simulation intensity).
  - mids → subtle color intensity lift.
  - treble → fine grain sparkle over wavefront.
- Wrapped final tone-map/dither in clamp to keep values in [0,1].
- Converted final `textureStore` to premultiplied alpha: `vec4<f32>(finalColor * finalAlpha, finalAlpha)`.
- Updated header Features comment to include `premultiplied-alpha`.

## Validation
`/root/.cargo/bin/naga public/shaders/gen-belousov-zhabotinsky.wgsl` → OK

## JSON updates
`shader_definitions/generative/gen-belousov-zhabotinsky.json` features array now includes:
`audio-reactive`, `aces-tone-map`, `ign-dither`, `premultiplied-alpha`.

## Lines after change
151
