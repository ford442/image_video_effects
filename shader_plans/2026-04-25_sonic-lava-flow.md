# Sonic Lava Flow (Real-time Fluid + Feedback)

## Overview
A Navier–Stokes-style fluid solver swirls over the video, mixing in decayed feedback for a lava-like melt.

## Shader Bindings
- `readTexture` for the base video
- `writeTexture` for final output
- `dataTextureA`/`dataTextureB` for velocity and pressure fields
- `writeDepthTexture` for fluid height/depth
- `plasmaBuffer` for color mapping

## How it works
- `dataTextureA` and `dataTextureB` (Bindings 7 and 8) ping-pong velocity and pressure data.
- `writeDepthTexture` (Binding 6) stores fluid height for depth blur.
- `readTexture` (Binding 1) shows the video beneath the flowing fluid.
- `writeTexture` (Binding 2) renders the fluid layer with molten color.

## Uniforms
- `u.zoom_config.yz` — acts as a local heat source pushing fluid outward.
- `u.zoom_params` — controls viscosity, turbulence, and decay.
- `u.config` — audio spikes increase viscosity and eddy size.

## Targets
- Shader: `public/shaders/gen-sonic-lava-flow.wgsl`
- JSON: `shader_definitions/artistic/gen-sonic-lava-flow.json`
