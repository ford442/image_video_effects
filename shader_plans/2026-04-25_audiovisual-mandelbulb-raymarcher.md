# Audiovisual Mandelbulb Raymarcher

## Overview
Render a true 3D fractal inside the video feed, mapping the video texture onto its surface and animating the geometry with audio. This is a raymarching overlay that blends the real video and a Mandelbulb-style fractal into one ornate, breathing scene.

## Shader Bindings
Uses the standard Pixelocity compute shader binding interface:
- `readTexture` for environment or surface texturing
- `writeDepthTexture` to output raymarch distance for depth-aware compositing
- `plasmaBuffer` for precomputed folding and fractal color gradients
- `writeTexture` for final frame output

## How it works
- Raymarch a 3D fractal per pixel instead of only applying 2D screen-space effects.
- `readTexture` (Binding 1) supplies the video as an environment map or surface texture.
- `writeDepthTexture` (Binding 6) writes the raymarch distance, enabling compositing with depth.
- `plasmaBuffer` (Binding 12) contains folding parameters and color gradient controls for fractal shading.

## Uniforms
- `u.zoom_config.yz` — rotates the camera around the fractal in real time.
- `u.zoom_params` — controls iteration count and escape radius.
- `u.config` — maps audio/time into fractal constants such as the Julia `C` value, causing the geometry to blossom and mutate with the music.

## Implementation notes
- Keep the raymarch budget bounded for real-time performance.
- Use the video feed to texturize the fractal surface or sky dome.
- Write depth to `writeDepthTexture` so the fractal can blend correctly with other layered effects.
- Drive fractal parameters with audio to give the structure a living, reactive motion.

## Targets
- Shader: `public/shaders/gen-audiovisual-mandelbulb-raymarcher.wgsl`
- JSON: `shader_definitions/generative/gen-audiovisual-mandelbulb-raymarcher.json`
