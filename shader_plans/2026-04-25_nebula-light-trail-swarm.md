# Nebula Light-Trail Swarm

## Overview
Tiny photon-like particles race through the scene, leaving glowing, fading trails that pulse with audio. This effect creates a constantly reforming nebula that breathes to the music.

## Shader Bindings
- `readTexture` as the base video/image input
- `writeTexture` for final output
- `extraBuffer` for per-particle state
- `dataTextureA` for the velocity field
- `plasmaBuffer` for color and glow mapping

## How it works
- `extraBuffer` (Binding 10) stores `[x, y, velocity, life]` for each particle.
- `dataTextureA` (Binding 7) holds a 2D velocity field built with curl noise that drags particles.
- `readTexture` (Binding 1) supplies the base scene and influences particle spawning.
- `writeTexture` (Binding 2) composites trails and particles into the final frame.
- `plasmaBuffer` (Binding 12) maps particle life/intensity into neon glow colors.

## Uniforms
- `u.zoom_config.yz` — mouse creates a repulsive bubble that pushes particles away.
- `u.zoom_params` — controls particle speed, life decay, trail length, and curl strength.
- `u.config` — audio boosts particle count and trail brightness during beats.

## Targets
- Shader: `public/shaders/gen-nebula-light-trail-swarm.wgsl`
- JSON: `shader_definitions/generative/gen-nebula-light-trail-swarm.json`
