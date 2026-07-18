# gen-langton-ant.wgsl upgrade notes

## Changes
- Added missing helpers `ign` and `huePreserveClamp` after existing `acesToneMap`.
- Added audio band reads: `mids = plasmaBuffer[0].y`, `treble = plasmaBuffer[0].z`.
- Enhanced audio reactivity:
  - bass → trail heat accumulation boost (existing `flipBoost`).
  - mids → heat-map hue rotation.
  - treble → ant-glyph brightness boost.
- Replaced final `acesToneMap(color * 1.2)` with `acesToneMap(huePreserveClamp(color, 2.0))` + `ign` dither + clamp.
- Converted final `textureStore` to premultiplied alpha while preserving `applyGenerativePrimaryControls`.
- Updated header Features comment to include `ign-dither` and `premultiplied-alpha`.

## Validation
`/root/.cargo/bin/naga public/shaders/gen-langton-ant.wgsl` → OK

## JSON updates
`shader_definitions/generative/gen-langton-ant.json` features array now includes:
`audio-reactive`, `aces-tone-map`, `ign-dither`, `premultiplied-alpha`.

## Lines after change
169
