# Chrono-Erosion (Feedback Melting)

## Overview
A datamosh-like flow effect where video content is swept away by an invisible vector field, leaving ornate melted trails that gracefully persist and fade. The result is a trippy feedback melting effect with controlled decay and audio-driven turbulence.

## Shader Bindings
Uses the standard Pixelocity compute shader binding interface:
- `readTexture` for current frame input
- `dataTextureC` for feedback of previous output
- `writeTexture` for blended final output
- `extraBuffer` for storing a grid of velocity vectors
- `plasmaBuffer` for flow modulation and color warping

## How it works
- `readTexture` (Binding 1) reads the current video frame.
- `dataTextureC` (Binding 9) reads the previous frame's final output for feedback.
- `writeTexture` (Binding 2) writes the blend of the current frame and displaced previous frame.
- `extraBuffer` (Binding 10) carries a slowly evolving grid of velocity vectors, updated with curl noise.
- `plasmaBuffer` (Binding 12) stores flow remap curves, color shifts, and velocity distortion parameters.

## Uniforms
- `u.zoom_config.yz` — adds directional velocity into the flow field so the mouse smudges the image like wet paint.
- `u.zoom_params` — controls feedback decay and flow intensity.
- `u.config` — audio spikes randomize or invert the flow field, producing shockwave melt effects.

## Implementation notes
- Use a simple feedback blend between current frame and warped previous frame.
- Store a procedural flow field in `extraBuffer`, evolving slowly with noise and user input.
- Keep decay parameterized so trails last only as long as desired.
- Add audio-reactive turbulence based on `u.config` to create dramatic melt pulses.

## Targets
- Shader: `public/shaders/gen-chrono-erosion-feedback-melting.wgsl`
- JSON: `shader_definitions/artistic/gen-chrono-erosion-feedback-melting.json`
