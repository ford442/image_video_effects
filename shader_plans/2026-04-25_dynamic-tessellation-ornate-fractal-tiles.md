# Dynamic Tessellation (Ornate Fractal Tiles)

## Overview
Compute a screen-space tile grid and replace each tile with a tiny procedurally rendered fractal. The result is a morphing lattice of fractal mini-universes.

## Shader Bindings
- `readTexture` for tile input or fallback pattern
- `writeTexture` for final tile composite
- `dataTextureA` for per-tile fractal parameters
- `plasmaBuffer` for fractal color palettes

## How it works
- `dataTextureA` (Binding 7) stores tile parameters such as seed, iteration depth, and transform.
- `plasmaBuffer` (Binding 12) provides palette curves for fractal rendering.
- Each tile is rendered small in-screen and stretched to fill its cell.
- `writeTexture` (Binding 2) composites the tile grid.

## Uniforms
- `u.zoom_config.yz` — dragging reseeds tiles and shifts the active region.
- `u.zoom_params` — controls iteration count, tile density, and fractal scale.
- `u.config` — audio increases iteration depth during beats.

## Targets
- Shader: `public/shaders/gen-dynamic-tessellation-ornate-fractal-tiles.wgsl`
- JSON: `shader_definitions/artistic/gen-dynamic-tessellation-ornate-fractal-tiles.json`
