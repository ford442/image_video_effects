# Cellular Automata Tapestry (Reaction-Diffusion)

## Overview
Convert the video feed into a living reaction-diffusion tapestry. This shader turns edges and faces into fingerprint-like swirls and zebra stripes, where the underlying video controls the chemistry of the simulation.

## Shader Bindings
Uses the standard Pixelocity compute shader binding interface:
- `readTexture` for video-driven feed/kill control
- `dataTextureA`/`dataTextureB` for reaction-diffusion ping-pong
- `plasmaBuffer` for psychedelic concentration-to-color mapping
- `writeTexture` for final composite output

## How it works
- `dataTextureA` and `dataTextureB` (Bindings 7 and 8) form the classic ping-pong buffers for concentrations of chemicals A and B.
- `readTexture` (Binding 1) uses video luminance to modulate feed/kill rates, allowing silhouettes to alter pattern formation.
- `plasmaBuffer` (Binding 12) maps chemical concentration differences into rich, neon gradients.
- `writeTexture` (Binding 2) renders the composite pattern over the source.

## Uniforms
- `u.zoom_config.yz` — injects Chemical B at the mouse position, letting users draw swirling motifs.
- `u.zoom_params` — base diffusion rates for chemicals A and B.
- `u.config` — audio-modulates the time step so the simulation speeds up and boils during drops.

## Implementation notes
- Use a stable Gray-Scott-like update step with texture sampling from the current state.
- Alternate writes between `dataTextureA` and `dataTextureB` each frame.
- Map concentration values through `plasmaBuffer` for a luxurious color palette.
- Keep the simulation responsive to both mouse and audio inputs.

## Targets
- Shader: `public/shaders/gen-cellular-automata-tapestry.wgsl`
- JSON: `shader_definitions/generative/gen-cellular-automata-tapestry.json`
