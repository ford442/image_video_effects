# gen-verlet-cloth-wind.wgsl upgrade notes

## Changes
- Added missing helpers `ign` and `huePreserveClamp` after existing `acesToneMap`.
- Added audio band reads: `mids = plasmaBuffer[0].y`, `treble = plasmaBuffer[0].z`.
- Enhanced audio reactivity:
  - bass → wind strength / specular pulse (existing, kept).
  - mids → fabric hue shift toward cool tones.
  - treble → weave grain shimmer amplitude.
- Replaced final `acesToneMap(color * 1.1)` with `acesToneMap(huePreserveClamp(color, 2.0))` + `ign` dither + clamp.
- Converted final `textureStore` to premultiplied alpha: `vec4<f32>(outColor * alpha, alpha)`.
- Updated header Features comment to include `ign-dither` and `premultiplied-alpha`.

## Validation
`/root/.cargo/bin/naga public/shaders/gen-verlet-cloth-wind.wgsl` → OK

## JSON updates
`shader_definitions/generative/gen-verlet-cloth-wind.json` features array now includes:
`audio-reactive`, `aces-tone-map`, `ign-dither`, `premultiplied-alpha`.

## Lines after change
155
