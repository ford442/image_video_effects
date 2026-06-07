# Psychedelic Layered Time-Stamps

## Overview
Overlay multiple delayed copies of the video, each with a different color offset and evolving distortion. The layers ripple and lag to create a kaleidoscopic time echo.

## Shader Bindings
- `readTexture` for the base video
- `writeTexture` for final output
- `dataTextureA` for per-layer delay offsets
- `plasmaBuffer` for color shift mapping

## How it works
- `dataTextureA` (Binding 7) stores delay offsets for each layer.
- `readTexture` (Binding 1) samples delayed frames or offsets from the base video.
- `plasmaBuffer` (Binding 12) provides HSV gradient shifts per layer.
- `writeTexture` (Binding 2) composites the layered ripple effect.

## Uniforms
- `u.zoom_config.yz` — selects which layer to tap and reset.
- `u.zoom_params` — controls number of layers, delay scale, and distortion amplitude.
- `u.config` — audio increases layer delay for beat-based ripples.

## Targets
- Shader: `public/shaders/gen-psychedelic-layered-time-stamps.wgsl`
- JSON: `shader_definitions/artistic/gen-psychedelic-layered-time-stamps.json`
