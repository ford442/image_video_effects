# New Shader Plan: Quantum Liquid-Metal Chronosphere

## Overview
A hyper-fluid, time-distorted sphere of oscillating liquid metal that continuously folds inward on itself, reflecting a synthetic quantum void.

## Features
- Dynamic raymarching of a smooth, undulating liquid-metal SDF
- Surface tension and displacement mapping driven by multi-octave simplex noise
- "Chronosphere" effect where time flows differently based on depth
- Chromatic aberration and Iridescent thin-film interference for metallic shading
- Mouse-interactive gravity well that pulls the metallic surface towards the cursor
- High-performance, unrolled distance estimation for fluid dynamics
- Ethereal bloom and ambient occlusion

## Technical Implementation
- File: public/shaders/gen-quantum-liquid-metal-chronosphere.wgsl
- Category: generative
- Tags: ["fluid", "metal", "quantum", "raymarching", "iridescent"]
- Algorithm: Raymarching of a smooth-min combined SDF with dynamic noise displacement and thin-film color mapping.

### Core Algorithm
The core is a raymarcher estimating the distance to a central sphere. The sphere's surface is heavily distorted by adding 3D simplex noise derived from world coordinates and time. We use smooth minimums (smin) to ensure the surface retains a liquid, cohesive quality rather than breaking into sharp fragments. A domain warping technique folds the space inside the sphere, creating a "chronosphere" illusion where the internal geometry twists.

### Mouse Interaction
The mouse cursor acts as a localized gravity well. We extract coordinates via `let mouse = u.zoom_config.yz;`. When the mouse is active (`u.zoom_config.w > 0.0`), the SDF applies a radial distortion, pulling the surface towards the ray mapped to the mouse coordinates, simulating a magnetic or gravitational attraction to the liquid metal.

### Color Mapping / Shading
The shading relies on a custom lighting model simulating metallic reflection. We calculate the surface normal using the gradient of the SDF. The base color is a dark, sleek chrome. As light hits the surface, we calculate a thin-film interference pattern (iridescence) using the dot product of the normal and the view direction, mixed with the elapsed time (`u.config.x`) and the noise value, mapped through a cosine palette to create shifting rainbow highlights.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Quantum Liquid-Metal Chronosphere
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
  zoom_params: vec4<f32>,  // .x = Fluid Density, .y = Surface Tension, .z = Flow Speed, .w = Iridescence Shift
  ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)

// Math and Noise functions
// Raymarching loop (map, calcNormal, march)
// Thin-film interference shading

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  // Compute shader entry point
}
```

## Parameters (for UI sliders)
- Fluid Density (`zoom_params.x`, default: 0.5, min: 0.0, max: 1.0)
- Surface Tension (`zoom_params.y`, default: 0.3, min: 0.1, max: 2.0)
- Flow Speed (`zoom_params.z`, default: 1.0, min: 0.1, max: 3.0)
- Iridescence Shift (`zoom_params.w`, default: 0.0, min: 0.0, max: 6.28)
