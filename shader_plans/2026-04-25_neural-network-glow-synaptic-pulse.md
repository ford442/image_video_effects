# Neural Network Glow (Synaptic Pulse)

## Overview
Render a glowing neural mesh and drive action-potential pulses with audio, creating a living synapse network that lights up in layers.

## Shader Bindings
- `readTexture` for mesh normal or depth data
- `writeTexture` for final glow output
- `dataTextureA` for pulse intensity state
- `plasmaBuffer` for glow palette mapping

## How it works
- `readTexture` (Binding 1) supplies a mesh normal map or depth map.
- `dataTextureA` (Binding 7) holds pulse intensity per vertex or node.
- `plasmaBuffer` (Binding 12) maps frequency bands to glow intensity gradients.
- `writeTexture` (Binding 2) draws the pulse-driven neural glow.

## Uniforms
- `u.zoom_config.yz` — clicking launches pulse waves from nodes.
- `u.zoom_params` — controls pulse speed, decay, and layer blend.
- `u.config` — audio drives different neural layers per frequency band.

## Targets
- Shader: `public/shaders/gen-neural-network-glow-synaptic-pulse.wgsl`
- JSON: `shader_definitions/generative/gen-neural-network-glow-synaptic-pulse.json`
