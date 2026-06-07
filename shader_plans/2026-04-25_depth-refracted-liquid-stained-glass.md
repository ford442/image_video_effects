# Depth-Refracted Liquid Stained Glass

## Overview
Transform the input video into a shattering, ornate cathedral window that feels tactile, refractive, and symmetrically kaleidoscopic. The shader combines depth extrusion, polar folding, and glass-like refraction for a luminous stained-glass effect.

## Shader Bindings
Uses the standard Pixelocity compute shader binding interface:
- `u_sampler` for smooth video sampling
- `readTexture` for the base video feed
- `readDepthTexture` for depth extrusion input
- `writeDepthTexture` for optional pseudo-depth output
- `plasmaBuffer` for chromatic aberration and IOR parameters
- `writeTexture` for final output

## How it works
- `readTexture` (Binding 1) provides the video content to be refracted and mirrored.
- `readDepthTexture` (Binding 4) is used to extrude the video into depth. If true depth is unavailable, derive pseudo-depth from luminance and write it into `writeDepthTexture` (Binding 6) in a preparatory pass.
- `u_sampler` (Binding 0) ensures smooth texture filtering through polar folding.
- `plasmaBuffer` (Binding 12) holds chromatic aberration offsets, index-of-refraction parameters, and facet tint curves.
- `writeTexture` (Binding 2) renders the final stained glass composite.

## Uniforms
- `u.zoom_config.yz` — moves the kaleidoscope center point across the screen.
- `u.zoom_params` — controls facet count and bevel width for the glass geometry.
- `u.config` — rotates the mirror geometry and modulates glass depth in time or audio-sync.

## Implementation notes
- Build a polar symmetry engine that folds UV coordinates into N facets.
- Use depth to offset refracted UVs, producing glassy extrusion and separation.
- Apply chromatic dispersion using `plasmaBuffer` as a small per-channel offset table.
- Add bevel and edge highlights to emphasize glass thickness.

## Targets
- Shader: `public/shaders/gen-depth-refracted-liquid-stained-glass.wgsl`
- JSON: `shader_definitions/artistic/gen-depth-refracted-liquid-stained-glass.json`
