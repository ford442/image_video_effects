# New Shader Plan: Celestial Prism-Orchid

## Overview
A mesmerizing, infinite expanse of refractive, crystalline petals that fold, bloom, and scatter starlight into vivid chromatic spectrums, dynamically responding to cosmic winds and audio vibrations.

## Features
- Refractive Petal KIFS: Procedurally generates endless overlapping crystalline petals.
- Audio-Reactive Blooming: The orchid's petals flare and unfold outward driven by audio frequencies (`u.config.y`).
- Chromatic Dispersion Shading: Simulates thick glass and prism indices of refraction, splitting white starlight into RGB fringes.
- Cosmic Wind Distortion: Domain-warped FBM noise creates a gentle, organic swaying motion through the petal layers.
- Starlight Core: An intensely glowing, volumetric plasma center that pulses and illuminates the surrounding petals.
- Mouse Gravity Well: The mouse acts as a localized gravity well, bending the petals slightly towards the cursor and shifting the refractive index.

## Technical Implementation
- File: public/shaders/gen-celestial-prism-orchid.wgsl
- Category: generative
- Tags: ["organic", "cosmic", "refractive", "audio-reactive", "raymarching", "fractal"]
- Algorithm: Raymarching a KIFS-based fractal structure combined with thin-film interference, volumetric core glowing, and chromatic aberration lighting.

### Core Algorithm
Uses folded spatial domains (Kaleidoscopic Iterated Function System - KIFS) combined with `sdCapsule` and `sdCappedCone` primitives to form petal-like layered structures. Domain warping via 3D FBM noise is applied before the SDF evaluation to give the petals a curved, organic, swaying feel simulating a cosmic wind.

### Mouse Interaction
The mouse position (`u.mouse`) creates a localized spherical distortion field that bends the space around the petals. The distance to the mouse modifies the primary fold angle in the KIFS, causing the orchid structure to dynamically "reach" or bend toward the cursor.

### Color Mapping / Shading
Employs a thick glass approximation by computing normal vectors and taking multiple offset lighting calculations to simulate chromatic aberration (separating R, G, and B reflections). The core emits a blazing radial plasma gradient, while the petals use a thin-film interference function to reflect iridescent colors (cyan, magenta, gold) based on the viewing angle (`dot(N, V)`).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Celestial Prism-Orchid
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// Structs
struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    mouse: vec4<f32>,
    zoom_params: vec4<f32>,
    config: vec4<f32>,
}

// Map function with KIFS and organic distortion
fn map(p: vec3<f32>) -> f32 {
    var pos = p;
    // Apply mouse distortion and cosmic wind (FBM)
    // Apply KIFS folds to create petals
    // Return SDF distance
    return 1.0;
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    // Finite difference approach
    return vec3<f32>(0.0, 1.0, 0.0);
}

// Raymarching loop
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    // Marching loop with max iterations
    return vec2<f32>(0.0, 0.0);
}

// Main compute shader
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // Setup UVs, camera, ray direction
    // Raymarch the scene
    // Apply chromatic dispersion shading & iridescent color mapping
    // Add glowing core based on audio (u.config.y)
    // Write out color
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Bloom Complexity (1.5, 0.1, 5.0, 0.1)
- Refractive Index (1.2, 1.0, 2.5, 0.01)
- Core Intensity (2.0, 0.0, 5.0, 0.1)
- Cosmic Wind Speed (0.5, 0.0, 2.0, 0.05)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
