# gen-cellular-automata-tapestry.wgsl upgrade notes

## Changes
- Added helpers `acesToneMap`, `ign`, `huePreserveClamp`, and `hash12` (for sparkle) after Uniforms struct.
- Audio band reads `bass/mids/treble` already existed; kept and enhanced.
- Enhanced audio reactivity:
  - bass → timestep pulse (`dt += bass * 0.3`).
  - mids → already modulated seasonal tint/alpha; left existing logic.
  - treble → added high-frequency sparkle to output color.
- Replaced direct `textureStore` with `acesToneMap(huePreserveClamp(outColor, 2.0))` + `ign` dither + clamp.
- Converted final `textureStore` to premultiplied alpha.
- Updated header Features comment to include `audio-reactive`, `aces-tone-map`, `ign-dither`, `premultiplied-alpha`.

## Validation
`/root/.cargo/bin/naga public/shaders/gen-cellular-automata-tapestry.wgsl` → OK

## JSON updates
`shader_definitions/generative/gen-cellular-automata-tapestry.json` features array now includes:
`audio-reactive`, `aces-tone-map`, `ign-dither`, `premultiplied-alpha`.

## Lines after change
171
