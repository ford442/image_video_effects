# Chromatic Vortex (Polar Distortion + Color-Space Warp)

## Overview
Rotate the image in polar coordinates while applying a psychedelic color-space warp. The effect combines dizzying spiral distortion with audio-driven RGB/YUV remapping.

## Shader Bindings
- `readTexture` for source imagery
- `writeTexture` for final output
- `dataTextureA` for the polar transform lookup table
- `plasmaBuffer` for the audio-driven color warp matrix

## How it works
- `dataTextureA` (Binding 7) holds a precomputed polar lookup table for radial transformations.
- `readTexture` (Binding 1) provides the base image that gets folded into the vortex.
- `plasmaBuffer` (Binding 12) stores a dynamic color-warp matrix that changes with audio.
- `writeTexture` (Binding 2) writes the twisted, color-shifted output.

## Uniforms
- `u.zoom_config.yz` — vortex center position.
- `u.zoom_params` — controls swirl strength, radius, and polar distortion.
- `u.config` — modulates the color matrix rows so loud audio turns hue shifts into luminance boosts.

## Targets
- Shader: `public/shaders/gen-chromatic-vortex.wgsl`
- JSON: `shader_definitions/artistic/gen-chromatic-vortex.json`
