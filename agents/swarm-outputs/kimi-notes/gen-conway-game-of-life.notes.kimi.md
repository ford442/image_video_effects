# gen-conway-game-of-life.wgsl upgrade notes

## Changes
- Helpers `acesToneMap`, `huePreserveClamp`, and `ign` already present.
- Added audio band reads: `mids = plasmaBuffer[0].y`, `treble = plasmaBuffer[0].z`.
- Enhanced audio reactivity:
  - bass → chromatic aberration and birth bloom (existing).
  - mids → (reserved via new audio bands; minimal direct use to avoid rule disruption).
  - treble → random sparkle added to cell color.
- Wrapped final tone-map/dither in clamp to keep values in [0,1].
- Converted final `textureStore` to premultiplied alpha: `vec4<f32>(outCol * alpha, alpha)`.
- Updated header Features comment to include `premultiplied-alpha`.

## Validation
`/root/.cargo/bin/naga public/shaders/gen-conway-game-of-life.wgsl` → OK

## JSON updates
`shader_definitions/generative/gen-conway-game-of-life.json` features array now includes:
`audio-reactive`, `aces-tone-map`, `ign-dither`, `premultiplied-alpha`.

## Lines after change
167
