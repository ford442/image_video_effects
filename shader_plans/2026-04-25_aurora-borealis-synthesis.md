# Aurora Borealis Synthesis

## Overview
Render a 3D volume of swirling aurora light and project it onto the 2D video surface, with audio-driven motion and depth-based mapping.

## Shader Bindings
- `readTexture` for the base video
- `writeTexture` for final output
- `dataTextureA` for the volumetric noise volume
- `plasmaBuffer` for aurora gradient colors

## How it works
- `dataTextureA` (Binding 7) encodes a 3D noise volume as a 2D slab.
- `readTexture` (Binding 1) provides the video to project the aurora onto.
- `plasmaBuffer` (Binding 12) contains aurora gradients from violet to neon green.
- `writeTexture` (Binding 2) composites the projected aurora ribbons.

## Uniforms
- `u.zoom_config.yz` — changes aurora storm direction.
- `u.zoom_params` — controls volume height, swirl speed, and brightness.
- `u.config` — bass drives upward motion while treble adds fine swirl.

## Targets
- Shader: `public/shaders/gen-aurora-borealis-synthesis.wgsl`
- JSON: `shader_definitions/artistic/gen-aurora-borealis-synthesis.json`
