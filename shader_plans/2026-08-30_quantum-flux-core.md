# New Shader Plan: Quantum Flux Core

## Overview
A hyper-energetic, mesmerizing visualization of a volatile quantum singularity, blending fluid plasma dynamics with intense particle-like energy fields that respond dynamically to interaction.

## Features
- Fluid plasma fields with multi-layered fractal noise
- Pulsating energy core with a magnetic displacement map
- Chromatic aberration and bloom for intense high-energy look
- Interactive gravity well driven by mouse movement
- Procedural glowing particle trails woven into the plasma
- Time-based phase shifting color palette

## Technical Implementation
- File: public/shaders/gen-quantum-flux-core.wgsl
- Category: generative
- Tags: ["quantum", "plasma", "energy", "fractal", "interactive"]
- Algorithm: Raymarching combined with multi-octave FBM (Fractional Brownian Motion) and dynamic SDFs for the core structure, perturbed by domain warping.

### Core Algorithm
The base structure relies on a smooth spherical SDF at the center, but its surface is heavily perturbed by a 4-octave 3D Simplex-style noise field (FBM). We raymarch this volatile surface. The empty space around the core is filled with volumetric raymarching accumulating emissive density based on another noise field to simulate glowing plasma arcs and particle flux.

### Mouse Interaction
The mouse cursor acts as a localized gravity well and magnetic disruptor. By dragging, the `u.zoom_config.yz` values shift the center of the SDF and violently increase the noise amplitude around the cursor radius, simulating ripping the quantum core.

### Color Mapping / Shading
Uses a phase-shifting cosine palette for hyper-saturated cyans, magentas, and deep purples. The core inner glow is intensely white/cyan (simulating extreme heat), cooling down to deep purple and black at the edges. Post-processing (within the pass) adds synthetic bloom by integrating the emissive values along the view ray.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Quantum Flux Core
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
  zoom_params: vec4<f32>,  // .x = Core Instability, .y = Plasma Density, .z = Energy Scale, .w = Phase Shift
  ripples: array<vec4<f32>, 50>,
};

// Math and Palette utilities
const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(TAU * (c * t + d));
}

// Custom 3D Noise for Flux
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453);
}

// ... Additional Noise, SDF, and Raymarching functions ...

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }

    // Convert to normalized coordinates and apply logic
    let uv = vec2<f32>(f32(global_id.x), f32(global_id.y)) / resolution;
    let base_uv = uv; // Store original uv for sampling if needed
    let aspect = resolution.x / resolution.y;
    let p = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);

    // ... Raymarching and plasma volume integration ...

    let final_color = vec3<f32>(0.0); // Placeholder

    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));
}
```

Parameters (for UI sliders)

- Core Instability (0.5, 0.0, 1.0, 0.01)
- Plasma Density (1.5, 0.1, 5.0, 0.1)
- Energy Scale (1.0, 0.5, 3.0, 0.05)
- Phase Shift (0.0, 0.0, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
