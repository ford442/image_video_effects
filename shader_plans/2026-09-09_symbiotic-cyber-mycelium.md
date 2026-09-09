# New Shader Plan: Symbiotic Cyber-Mycelium

## Overview
A mesmerizing descent into a synthetic fungal network where glowing bioluminescent fibers transmit digital pulses between pulsating data-nodes. It bridges the gap between organic growth algorithms and rigid, luminous cybernetic aesthetics.

## Features
- Generative 3D Raymarching with branching organic-looking SDF structures.
- Pulsating data packets traveling along the procedural mycelial fibers using modulo-based time offsets.
- Mouse-driven "infection" field that distorts the local network space and accelerates data flow.
- A neon-infused Cyberpunk color palette: toxic greens, vibrant magentas, and deep ultraviolet blues.
- Subsurface scattering approximation for the organic tissue, blended with sharp emissive blooms for the data pulses.
- Audio-reactive growth and pulsing (if extended to audio), mapped to density and speed.
- Infinite procedural domain repetition to create a vast, immersive micro-verse.

## Technical Implementation
- File: public/shaders/gen-symbiotic-cyber-mycelium.wgsl
- Category: generative
- Tags: ["3d", "raymarching", "organic", "cyberpunk", "mycelium", "neon", "sdf"]
- Algorithm: Raymarching infinite 3D domain repetition with fractal branching cylinders and glowing spheres.

### Core Algorithm
The scene is built using a primary Raymarching loop over a folded/repeated 3D space (`opRep`). The core SDF combines a smooth-unioned grid of spheres (data nodes) with fractalized, sine-distorted cylinders (mycelial threads). We apply domain twisting (`p.xy *= rot(p.z * twistFactor)`) to give the fibers an organic, tangled feel. A 3D FBM noise offsets the SDF distance slightly to create a bumpy, organic texture on the fibers.

### Mouse Interaction
The mouse acts as a central "data injection" point. Its `xy` position is mapped to an interaction radius in 3D space. As rays approach the `vec3(mouse_uv, depth)` locus, the space is radially distended (a gravity-well/lens effect), and the emission intensity of the mycelial network in that zone is multiplied by a user-defined factor.

### Color Mapping / Shading
Base shading utilizes simple diffuse and a cheap Subsurface Scattering hack (`SDF(p + N * 0.1) * 10.0`). The glowing data packets are mapped by taking the fractional part of the distance along the fibers minus time (`fract(length(p.xy) * 5.0 - u.config.x * speed)`), triggering a sharp step-function bloom. The color palette relies on a branchless cosine palette `a + b * cos(2pi * (c*t + d))` to blend neon green into magenta.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Symbiotic Cyber-Mycelium
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
  zoom_params: vec4<f32>,  // .x = Data Speed, .y = Network Density, .z = Growth Twist, .w = Infection Bloom
  ripples: array<vec4<f32>, 50>,
};

// ... (Constants, rotation matrices, noise functions)

// fn map(p: vec3<f32>) -> vec2<f32> (SDF and material ID)
// fn calcNormal(p: vec3<f32>) -> vec3<f32>
// fn palette(t: f32) -> vec3<f32>

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // 1. Setup uv and camera
    // 2. Raymarch loop
    // 3. Shading, bloom, and SSS
    // 4. Output to textureStore(writeTexture, ...)
}
```

Parameters (for UI sliders)

Data Speed (1.0, 0.1, 5.0, 0.1)
Network Density (2.0, 0.5, 5.0, 0.1)
Growth Twist (0.5, 0.0, 2.0, 0.05)
Infection Bloom (1.5, 0.0, 5.0, 0.1)
