# New Shader Plan: Chrono-Luminescent Voxel Citadel

## Overview
A majestic, constantly shifting cityscape of glowing, translucent voxels that rebuilds itself based on time and audio reactivity.

## Features
- Ethereal, grid-based voxel marching algorithm
- Time-distorted geometry that ebbs and flows
- Subsurface scattering effect within glowing blocks
- Audio-reactive heights and emission intensities
- Neon color gradients mapped to vertical elevation
- Mouse-controlled orbital camera with gravity well distortions
- Deep temporal anti-aliasing (TAA) integration

## Technical Implementation
- File: public/shaders/gen-chrono-luminescent-voxel-citadel.wgsl
- Category: generative
- Tags: ["voxel", "cityscape", "neon", "audio-reactive", "time"]
- Algorithm: Raymarching against a 3D grid with domain repetition and hashed heights.

### Core Algorithm
Raymarching a quantized space. We take the continuous 3D position and floor it to get discrete voxel coordinates. Using a hash function on the voxel coordinates, we determine the height and color of each column. A 3D DDA (Digital Differential Analyzer) or simplified ray-box intersection is used to step through the grid efficiently. Audio data from `plasmaBuffer[0]` modulates the base height hash.

### Mouse Interaction
The mouse click (`u.zoom_config.w > 0.5`) bends the rays toward the center, creating a localized gravity well effect that warps the voxel grid, twisting the cityscape around the mouse coordinates.

### Color Mapping / Shading
Colors transition from deep indigo at the base to neon cyan and magenta at the peaks. The shader fakes subsurface scattering by accumulating glow based on the distance light travels through the voxels, and uses metallic shading on the surface.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Chrono-Luminescent Voxel Citadel
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,              // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,         // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,         // .xyzw = user params p1..p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};
// ... (full skeleton with comments)
```
Parameters (for UI sliders)

Name (default, min, max, step)
Voxel Density (0.5, 0.1, 1.0, 0.1)
Audio Reactivity (0.8, 0.0, 1.0, 0.05)
Color Shift (0.0, -1.0, 1.0, 0.01)
Gravity Well Strength (0.5, 0.0, 1.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
