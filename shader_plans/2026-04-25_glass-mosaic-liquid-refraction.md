# Glass Mosaic + Liquid Refraction

## Overview
Treat the video as a stained-glass pane sliced into polygons, then refract it through a pseudo-depth height map for an ornate liquid-glass composite.

## Shader Bindings
- `readTexture` for the base video
- `writeTexture` for final output
- `readDepthTexture` for depth extrusion input
- `writeDepthTexture` to store fractured depth results
- `plasmaBuffer` for distortion LUTs

## How it works
- `readDepthTexture` (Binding 4) is either native depth or pseudo-depth generated from luminance.
- `writeDepthTexture` (Binding 6) stores fractured depth for depth-aware compositing.
- `plasmaBuffer` (Binding 12) supplies UV offsets per depth slice for refraction.
- `readTexture` (Binding 1) is refracted through the glass mosaic arrangement.

## Uniforms
- `u.zoom_config.yz` — drags the glass center, letting the user peel away panes.
- `u.zoom_params` — controls facet count and refractive bevel width.
- `u.config` — audio causes the glass to ripple and oscillate.

## Targets
- Shader: `public/shaders/gen-glass-mosaic-liquid-refraction.wgsl`
- JSON: `shader_definitions/artistic/gen-glass-mosaic-liquid-refraction.json`
