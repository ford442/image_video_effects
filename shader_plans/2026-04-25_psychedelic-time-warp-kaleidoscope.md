# Psychedelic Time-Warp Kaleidoscope

## Overview
Mirror the image around a dynamic axis with a time-varying mirror count. Reflection vectors are distorted by a 3D noise field for a shimmering kaleidoscope.

## Shader Bindings
- `readTexture` for the input image
- `writeTexture` for final output
- `dataTextureA` for the 3D curl-noise field
- `plasmaBuffer` for mirror count waveform data

## How it works
- `dataTextureA` (Binding 7) stores a 3D curl-noise field.
- `plasmaBuffer` (Binding 12) contains a sine-wave table for mirror count modulation.
- `readTexture` (Binding 1) is mirrored with oscillating axis geometry.
- `writeTexture` (Binding 2) outputs the kaleidoscope.

## Uniforms
- `u.zoom_config.yz` — positions the center of the kaleidoscope.
- `u.zoom_params` — controls mirror strength, wobble amount, and noise intensity.
- `u.config` — audio modulates the speed of mirror-count oscillation.

## Targets
- Shader: `public/shaders/gen-psychedelic-time-warp-kaleidoscope.wgsl`
- JSON: `shader_definitions/artistic/gen-psychedelic-time-warp-kaleidoscope.json`
