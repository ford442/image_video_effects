# Magnetic Field Warp (Quadratic Distortion + Spectral Modulation)

## Overview
Treat the image as charged particles warped by a magnetic field. UVs are distorted quadratically and colors are remapped through a spectral histogram.

## Shader Bindings
- `readTexture` for the source image
- `writeTexture` for final output
- `dataTextureA` for the magnetic field map
- `plasmaBuffer` for spectral histogram and color remapping

## How it works
- `dataTextureA` (Binding 7) stores a 2D magnetic field map representing ∇ × A.
- `readTexture` (Binding 1) provides the image to be warped.
- `plasmaBuffer` (Binding 12) maps audio frequencies to color remap curves.
- `writeTexture` (Binding 2) writes the warped, plasma-tinted output.

## Uniforms
- `u.zoom_config.yz` — creates a magnetic dipole that distorts nearby pixels.
- `u.zoom_params` — controls warp strength, field curvature, and spectral intensity.
- `u.config` — audio pulses drive magnetic pulses across the image.

## Targets
- Shader: `public/shaders/gen-magnetic-field-warp.wgsl`
- JSON: `shader_definitions/artistic/gen-magnetic-field-warp.json`
