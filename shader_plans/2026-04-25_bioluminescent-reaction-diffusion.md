# Bioluminescent Reaction-Diffusion

## Overview
Classic Gray-Scott reaction-diffusion driven by video luminance, with the concentration map mapped through a neon bioluminescent LUT.

## Shader Bindings
- `readTexture` for video luminance control
- `writeTexture` for final glow composite
- `dataTextureA`/`dataTextureB` for ping-pong chemical state
- `plasmaBuffer` for neon gradient mapping

## How it works
- `dataTextureA` and `dataTextureB` (Bindings 7 and 8) hold chemical concentrations for the reaction.
- `readTexture` (Binding 1) uses luminance to directly set feed/kill rates.
- `plasmaBuffer` (Binding 12) converts concentration values into rich iridescent colors.
- `writeTexture` (Binding 2) renders the glowing reaction result.

## Uniforms
- `u.zoom_config.yz` — injects Chemical B into the simulation as a bioluminescent bubble.
- `u.zoom_params` — base diffusion and reaction rate controls.
- `u.config` — audio spikes reduce diffusion, tightening blooms.

## Targets
- Shader: `public/shaders/gen-bioluminescent-reaction-diffusion.wgsl`
- JSON: `shader_definitions/generative/gen-bioluminescent-reaction-diffusion.json`
