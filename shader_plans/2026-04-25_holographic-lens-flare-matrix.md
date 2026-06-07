# Holographic Lens-Flare Matrix

## Overview
Generate a matrix of holographic lens flares that follow motion in the video or a synthetic flow field. The flares are volumetric glow shells that twist in 3D.

## Shader Bindings
- `readTexture` for motion or input texture
- `writeTexture` for final flare composite
- `extraBuffer` for per-flare state
- `dataTextureA` for volumetric density field
- `plasmaBuffer` for flare palette

## How it works
- `extraBuffer` (Binding 10) stores `[x, y, z, rotation]` for each flare.
- `dataTextureA` (Binding 7) encodes a volumetric density field for soft-body blur.
- `plasmaBuffer` (Binding 12) provides a polychrome palette for flare glow.
- `writeTexture` (Binding 2) renders the holographic matrix.

## Uniforms
- `u.zoom_config.yz` — pushes flares apart to create waves.
- `u.zoom_params` — controls flare density, brightness, and rotation.
- `u.config` — audio scales flare size and spin speed.

## Targets
- Shader: `public/shaders/gen-holographic-lens-flare-matrix.wgsl`
- JSON: `shader_definitions/artistic/gen-holographic-lens-flare-matrix.json`
