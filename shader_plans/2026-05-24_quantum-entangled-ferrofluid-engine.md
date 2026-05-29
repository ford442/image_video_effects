# New Shader Plan: Quantum-Entangled Ferrofluid Engine

## Overview
A pulsating, zero-gravity containment field where hyper-magnetic liquid metal aggressively self-organizes into intricate, audio-reactive ferrofluid spikes, refracting quantum light through its shifting geometry.

## Features
- Volumetric, Raymarched Ferrofluid: A colossal, morphing sphere of liquid metal with dynamic spike generation.
- Quantum-Entangled Spikes: Magnetic spikes that react violently to audio frequencies, merging and splitting like chaotic liquid algorithms.
- Iridescent Oil-Slick Specularity: Chromatic aberration and thin-film interference playing across the metallic surface based on view angle and normal curvature.
- Zero-Gravity Magnetic Fields: Floating droplets of liquid metal orbiting the central engine mass, merging seamlessly using soft minimums.
- Mouse-Driven Magnetic Anomaly: The mouse acts as a localized hyper-magnet, pulling and distorting the ferrofluid towards the cursor in 3D space.

## Technical Implementation
- File: public/shaders/gen-quantum-entangled-ferrofluid-engine.wgsl
- Category: generative
- Tags: ["fluid", "magnetic", "metallic", "audio-reactive", "quantum", "abstract"]
- Algorithm: Raymarching an SDF sphere heavily modulated by multi-octave 3D Simplex noise and audio-driven high-frequency displacement.

### Core Algorithm
The base shape is an SDF sphere located at the origin. The surface is continuously displaced using Fractal Brownian Motion (FBM) layered with 3D noise. The noise coordinates are translated by time and scaled by ambient audio input (`u.config.y`). High-frequency audio triggers sharp, needle-like spike generation using absolute noise formulas. Small, independent droplets are generated using spatial domain repetition and blended back into the main body using polynomial smooth minimum (`smin`) for organic fluid merging.

### Mouse Interaction
The mouse coordinates (`u.zoom_config.y`, `u.zoom_config.z`) position a virtual magnetic singularity in the 3D space. The SDF evaluates the proximity of the ray to this singularity and applies a localized directional warp (gravity well), elongating and stretching the ferrofluid spikes directly towards the user's pointer.

### Color Mapping / Shading
A physically based rendering (PBR) approximation is used, characterized by extreme specularity and low roughness. The base diffuse albedo is pitch black (like obsidian). Reflections incorporate a dynamic iridescent gradient (shifting between cyan, magenta, and gold) driven by the Fresnel effect (view angle relative to the normal). Intense bloom is isolated to high-specular highlights to simulate intense quantum energy leaks.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Quantum-Entangled Ferrofluid Engine
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

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
    ripples: array<vec4<f32>, 50>,
};

// --- HELPER FUNCTIONS ---
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(p: vec3<f32>) -> f32 {
    // Base sphere
    var d = length(p) - 2.0;

    // Audio reactive noise displacement
    // ...

    return d;
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // Raymarching loop and rendering logic
    // ...
}
```

## Parameters (for UI sliders)
- Magnetic Intensity (1.5, 0.0, 5.0, 0.1)
- Spike Sharpness (2.0, 0.5, 4.0, 0.1)
- Iridescence Shift (0.5, 0.0, 1.0, 0.05)
- Fluid Viscosity (1.0, 0.1, 3.0, 0.1)

## Integration Steps
1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
