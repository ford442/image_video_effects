# New Shader Plan: Fractal Chrono-Dendrite Forge

## Overview
A hyper-intricate procedural branching structure simulating crystalline growth and decay through a spacetime distortion field, rendered with a bismuth-iridescent glass aesthetic.

## Features
- **Fractal Spanning Trees:** L-system inspired 3D recursive paths representing chronological dendrites.
- **Iridescent Glass Material:** Subsurface scattering simulation and spectral dispersion for a bismuth-like look.
- **Chronological Decay Waves:** Rippling pulses of entropy that shatter and rebuild branches based on time and audio input.
- **Volumetric Caustics:** Ambient light transmission simulating dense, refracting temporal fluid.
- **Audio-Reactive Synapses:** Bright kinetic sparks traveling along the dendrite nodes synchronized with audio frequency.
- **Gravitational Mouse Pull:** Mouse interaction creates localized black hole anomalies, warping the dendrite paths toward the cursor.

## Technical Implementation
- File: public/shaders/gen-fractal-chrono-dendrite-forge.wgsl
- Category: generative
- Tags: ["fractal", "dendrite", "time-manipulation", "bismuth", "glass", "audio-reactive"]
- Algorithm: Raymarching an Apollonian gasket mixed with L-system branching SDFs, shaded via physically-inspired spectral iridescence.

### Core Algorithm
Raymarching scene combining branching cylindrical SDFs (dendrites) intersecting with folded Apollonian spheres (chronos nodes). The domain is repetitively folded using recursive modulus operations to create the infinite fractal density. Noise buffers distort the paths over time to simulate organic growth.

### Mouse Interaction
The cursor position (`u.zoom_config.yz`) acts as a gravitational singularity. Distance from the ray to the cursor coordinates scales space non-linearly using an inverse square law, smoothly bending ray vectors and pulling the dendrite branches inward, creating a warped fisheye-like vortex effect.

### Color Mapping / Shading
Bismuth spectral dispersion calculated by mapping the SDF normal's dot product with the view vector to a cosine gradient palette. Multiple layers of fractional noise control the thickness of an imaginary thin-film layer for interference coloring. High specularity with bloom passes to create a deep, glowing glass-like volume.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Fractal Chrono-Dendrite Forge
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=Param
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ----------------------------------------------------------------
// CONSTANTS & UTILITIES
// ----------------------------------------------------------------
const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 120;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

// Rotations, Hash, and Noise functions
fn rot2D(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// ----------------------------------------------------------------
// SCENE SDF
// ----------------------------------------------------------------
fn map(p: vec3<f32>) -> f32 {
    // 1. Base Dendrite Branching
    // 2. Chronos Node Intersections
    // 3. Spacetime Distortion (Mouse gravity)
    // Return distance
    return length(p) - 1.0; // Placeholder
}

// ----------------------------------------------------------------
// NORMALS & SHADING
// ----------------------------------------------------------------
fn getNormal(p: vec3<f32>) -> vec3<f32> {
    // Standard normal calculation via swizzled gradients
    return vec3<f32>(0.0, 1.0, 0.0);
}

// Spectral Interference colors for bismuth look
fn getBismuthColor(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.0, 0.33, 0.67);
    return a + b * cos(6.28318 * (c * t + d));
}

// ----------------------------------------------------------------
// MAIN RENDER LOOP
// ----------------------------------------------------------------
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

    // UV Setup & Camera

    // Raymarching

    // Shading & Composition

    // Output
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(0.0));
}
```

## Parameters (for UI sliders)

- `zoom_params.x`: Dendrite Complexity (1.0, 0.0, 5.0, 0.1)
- `zoom_params.y`: Entropy Pulse Rate (0.5, 0.0, 2.0, 0.05)
- `zoom_params.z`: Spectral Dispersion (1.2, 0.1, 3.0, 0.1)
- `zoom_params.w`: Gravity Well Strength (0.8, 0.0, 2.0, 0.1)