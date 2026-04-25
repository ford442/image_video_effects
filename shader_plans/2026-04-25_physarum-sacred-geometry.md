# Physarum (Slime Mold) "Sacred Geometry"

## Overview
A psychedelic organic simulation where millions of microscopic agents feed on video input, leaving vibrant, glowing, fractal trails that pulse with audio. The effect blends slime mold growth, trail diffusion, and ornate color mapping into a living, sacred-geometry visual.

## Shader Bindings
Uses the standard Pixelocity compute shader binding interface:
- `readTexture` as nutrient density
- `writeTexture` for the final composited output
- `dataTextureA`/`dataTextureC` for trail ping-pong
- `extraBuffer` for agent state
- `plasmaBuffer` for color LUT

## How it works
- `extraBuffer` (Binding 10) stores agent state: `[x, y, angle, state]` for a dense swarm of particles.
- `readTexture` (Binding 1) supplies nutrient density from the video; brighter pixels attract the agents.
- `dataTextureC` (Binding 9) holds the current chemical trail map for sensing.
- `dataTextureA` (Binding 7) receives deposited pheromones from each agent.
- A second compute pass blurs and decays the trail map to create soft, glowing edges.
- `plasmaBuffer` (Binding 12) is used as an ornate color lookup table, mapping trail density to iridescent, psychedelic colors.
- `writeTexture` (Binding 2) outputs the final composite.

## Uniforms
- `u.zoom_config.yz` — mouse repellent. Drag the mouse to part the slime like Moses parting the Red Sea.
- `u.zoom_params` — sensor angle, sensor distance, decay rate, diffusion strength.
- `u.config` — audio controls agent rotation speed and scattering intensity. Loud beats trigger starburst dispersion.

## Implementation notes
- Use a dual-pass pipeline: pass 1 simulates agents and writes trails, pass 2 blurs/decays the trail map.
- Keep the particle state compact in `extraBuffer` and use `dataTextureC` only for sensing density.
- Map trail intensity through `plasmaBuffer` into rich, shifting color palettes.
- Consider a parameterized `repelRadius` around `u.zoom_config.yz` so the cursor acts as a live control point.

## Targets
- Shader: `public/shaders/gen-physarum-sacred-geometry.wgsl`
- JSON: `shader_definitions/generative/gen-physarum-sacred-geometry.json`
- Add UI mapping for audio-reactive and mouse-driven controls.
