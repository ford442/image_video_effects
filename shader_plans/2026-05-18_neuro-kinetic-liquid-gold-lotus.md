# New Shader Plan: Neuro-Kinetic Liquid-Gold Lotus

## Overview
A hyper-organic, slowly unfurling macro-lotus made of liquid-gold geometry that dynamically responds to acoustic impulses, its petals rippling with neuro-kinetic plasma energy.

## Features
- Infinite unfurling geometric lotus petals constructed via radial SDFs.
- Liquid-gold material properties with high spectral dispersion and environment mapping approximations.
- Neuro-kinetic plasma veins that pulse through the petals in sync with low-frequency audio.
- Audio-reactive blooming: the entire structure expands and dilates its core based on the audio amplitude.
- Interactive gravity-well: mouse movements warp the surrounding liquid-aether, bending the petals towards the cursor.

## Technical Implementation
- File: public/shaders/gen-neuro-kinetic-liquid-gold-lotus.wgsl
- Category: generative
- Tags: ["organic", "liquid", "gold", "audio-reactive", "geometry"]
- Algorithm: Raymarching radial SDFs combined with domain warping and fluid noise dynamics.

### Core Algorithm
Raymarching a complex scene using `sdCylinder` and `sdSphere` modified by `opTwist` and radial domain repetition (`atan2` + `mod`). Petals are shaped by intersecting modified spheres and applying fractional Brownian motion (fBm) to the surface for the liquid texture.

### Mouse Interaction
The mouse acts as a localized gravity and temporal distortion field. When close to the center, it bends the raymarching direction using a smooth quadratic falloff, simulating a localized black hole that pulls the liquid-gold petals toward the cursor.

### Color Mapping / Shading
A custom metallic PBR approximation. The liquid-gold effect uses a base yellow/orange gradient with high specularity, mixed with a rim-light driven by the normals and dot-products. The neuro-kinetic plasma veins use an emissive cyan-magenta color palette that overrides the gold when the acoustic energy (read from the audio uniform) peaks.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Neuro-Kinetic Liquid-Gold Lotus
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    mouse: vec4<f32>,
    audio_data: vec4<f32>,
    // Add additional custom uniforms if needed
}

// Pseudocode for raymarching and sdf
fn sdPetal(p: vec3<f32>) -> f32 {
    // ...
    return length(p) - 1.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // 1. Ray setup and camera projection
    // 2. Domain repetition and twisting
    // 3. Raymarching loop (sphere tracing)
    // 4. Lighting and liquid-gold shading
    // 5. Plasma vein overlay based on u.audio_data
    // 6. Write to texture
}
```

## Parameters (for UI sliders)

Bloom Radius (1.0, 0.1, 5.0, 0.1)
Plasma Intensity (0.5, 0.0, 2.0, 0.05)
Gold Smoothness (0.8, 0.0, 1.0, 0.01)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
