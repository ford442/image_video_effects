# New Shader Plan: Luminescent Silica Diatom Swarm

## Overview
A mesmerizing descent into a microscopic oceanic ecosystem where bioluminescent silica structures swarm and orbit, weaving crystalline light through fluid caustics.

## Features
- Intricate, microscopic, glassy structural aesthetics (diatoms)
- Bioluminescent subsurface scattering and internal refraction
- Fluid-like spatial turbulence and domain folding
- Audio-reactive light bursts and swarm density shifts
- Deep underwater ambient occlusion and depth of field

## Technical Implementation
- File: public/shaders/gen-luminescent-silica-diatom-swarm.wgsl
- Category: generative
- Tags: ["microscopic", "glass", "bioluminescent", "swarm", "fluid", "audio-reactive"]
- Algorithm: Raymarching through domain-folded spaces with complex Voronoi-based structural noise and multi-layered sub-surface color transmission.

### Core Algorithm
The environment will utilize multi-octave 3D Simplex and Voronoi noise mapped to raymarching distances to carve out silica-like shells. Space will be heavily domain-folded (using modulus logic) to create an infinite "swarm" of these structures. Audio reactivity will drive the scale and rotation matrices of the domain folding, pulsing the swarm.

### Mouse Interaction
The mouse acts as a localized thermal/gravity well. As `zoom_config.yz` approaches a coordinate, the swarm will radially warp away (using an inverse-square distance displacement on the coordinates) and change the bioluminescent hue (e.g., from deep cyan to intense warm gold) near the cursor.

### Color Mapping / Shading
Materials will simulate glass through ray-bending approximations and reflection (using normal mapping and Schlick's approximation for Fresnel). Internal structure will map `dataTextureC` (audio) directly to inner emission brightness and hue shift, creating a pulsating, glowing core effect against dark, deep-water background gradients.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Luminescent Silica Diatom Swarm
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Swarm Density, .y = Bioluminescence, .z = Glass Refraction, .w = Audio Reactivity
  ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```
Parameters (for UI sliders)

Name (default, min, max, step)
- Swarm Density (1.0, 0.1, 5.0, 0.1) -> zoom_params.x
- Bioluminescence (1.5, 0.0, 5.0, 0.1) -> zoom_params.y
- Glass Refraction (1.33, 1.0, 2.5, 0.01) -> zoom_params.z
- Audio Reactivity (1.0, 0.0, 3.0, 0.1) -> zoom_params.w

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-08-20_luminescent-silica-diatom-swarm.md" "Luminescent Silica Diatom Swarm"
