# New Shader Plan: Void Crystal Engine

## Overview
A hyper-geometric, slowly mutating tesseract of dark matter crystals, utilizing deep internal refraction and chromatic dispersion.

## Features
- Ethereal floating crystal structures built with Signed Distance Fields (SDFs)
- Chromatic dispersion simulating internal light refraction
- Smooth min/max blending for organic, morphing sharp edges
- Reactive glow based on bass frequencies from plasmaBuffer
- Cosmic dust particle system in the background

## Technical Implementation
- File: public/shaders/gen-void-crystal-engine.wgsl
- Category: generative
- Tags: ["crystal", "void", "dark-matter", "refraction", "cosmic"]
- Algorithm: Raymarching an SDF scene with folded space and chromatic aberration.

### Core Algorithm
Raymarching a scene built from octahedron and box SDFs. The space is folded using `p = abs(p) - offset` repeatedly to create fractal-like crystal clusters. We calculate normals for fake refraction, offsetting the read ray based on color channels (chromatic dispersion).

### Mouse Interaction
When `u.zoom_config.w > 0.5`, the mouse position (`u.zoom_config.yz`) acts as a gravity well, bending the ray trajectories towards the mouse, distorting the crystal lattice locally.

### Color Mapping / Shading
The shading uses a dark, void-like palette (deep purples and blacks) for the background, while the crystals themselves are highly refractive, catching bright cyan and magenta highlights. We sample `plasmaBuffer[0].x` to pulse the emission of the core crystals.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Void Crystal Engine
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

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(id.xy) / resolution;

    // Core raymarching loop here

    let color = vec4<f32>(0.0, 0.0, 0.0, 1.0); // Placeholder
    textureStore(writeTexture, vec2<i32>(id.xy), color);
}
```
Parameters (for UI sliders)

Name (default, min, max, step)
- Crystal Density (0.5, 0.1, 1.0, 0.05)
- Refraction Index (1.2, 1.0, 2.0, 0.01)
- Dispersion (0.1, 0.0, 0.5, 0.01)
- Core Pulse (0.8, 0.0, 1.0, 0.05)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
