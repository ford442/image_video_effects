# New Shader Plan: Stellar Mycelium Overdrive

## Overview
A hyper-organic network of glowing stardust mycelium that dynamically branches, pulses with cosmic energy, and responds to gravity wells.

## Features
- Procedurally generated branching structures resembling cosmic fungus.
- Bioluminescent energy pulses traveling along the network paths.
- Volumetric glowing fog mimicking nebulae surrounding the nodes.
- Mouse interaction creates a localized gravitational distortion, pulling mycelium tendrils.
- Dynamic color shifts based on audio reactivity or temporal oscillation.
- Smooth SDF blending for organic, continuous structures.

## Technical Implementation
- File: public/shaders/gen-stellar-mycelium-overdrive.wgsl
- Category: generative
- Tags: ["organic", "cosmic", "mycelium", "sdf", "bioluminescent"]
- Algorithm: Raymarching through domain-warped SDFs combined with fractional Brownian motion (fBm) for branching logic.

### Core Algorithm
Utilizes a 3D raymarching engine. The base structure is generated using Gyroid SDFs, heavily distorted by 3D fBm noise to simulate the chaotic yet structured branching of mycelium. Domain repetition is applied with overlapping scales to create a dense, infinite network.

### Mouse Interaction
When `u.zoom_config.w > 0.5`, the mouse position `u.zoom_config.yz` acts as a gravity well. The space around the mouse is warped using a smooth polynomial falloff, pulling the Gyroid nodes towards the cursor and increasing the local energy pulse intensity.

### Color Mapping / Shading
Shading relies on physically-inspired subsurface scattering approximation. A base metallic purple/blue palette shifts to bright neon cyan/pink at the branch tips. Volumetric bloom is accumulated during raymarching based on step distance to simulate the glowing nebular gas.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Stellar Mycelium Overdrive
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

// SDF functions
fn sdGyroid(p: vec3<f32>, scale: f32, thickness: f32, bias: f32) -> f32 {
    let p_scaled = p * scale;
    return abs(dot(sin(p_scaled), cos(p_scaled.zxy)) - bias) / scale - thickness;
}

// Map function
fn map(pos: vec3<f32>) -> f32 {
    // Basic structure
    var d = sdGyroid(pos, 5.0, 0.05, 0.0);
    // Add distortion here based on mouse
    return d;
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // Compute shader logic
    // Setup camera, ray direction
    // Raymarching loop
    // Coloring and bloom
    // Output to texture
}
```
Parameters (for UI sliders)

Density (1.0, 0.1, 5.0, 0.1)
Pulse Speed (1.0, 0.0, 3.0, 0.1)
Glow Intensity (2.0, 0.0, 5.0, 0.1)
Color Shift (0.5, 0.0, 1.0, 0.05)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
