# New Shader Plan: Abyssal Leviathan-Scales

## Overview
A mesmerizing, infinite expanse of massive, interlocking biomechanical armor scales that undulate like a breathing cosmic leviathan, parting to reveal a blazing, audio-reactive quantum fusion core beneath.

## Features
- Infinite, undulating plane of overlapping biomechanical scales using domain repetition and hexagonal grid mapping.
- Breathing, organic motion using FBM-driven wave displacement.
- Glowing quantum fusion core revealed in the gaps between the scales, reacting violently to audio amplitude (`u.config.y`).
- Subsurface scattering effect on the scales to give them a dark, iridescent, oily sheen.
- Mouse interaction acts as a magnetic repulsor, violently forcing the scales to open up and expose the inner light.
- Raymarched volumetric glow for the deep plasma veins.

## Technical Implementation
- File: public/shaders/gen-abyssal-leviathan-scales.wgsl
- Category: generative
- Tags: ["organic", "mechanical", "quantum", "raymarching", "bioluminescence"]
- Algorithm: Raymarching an undulating hexagonal grid of domed, interlocking scale SDFs, layered over a bright emissive plasma under-layer.

### Core Algorithm
Uses a 2D hexagonal domain repetition on the XZ plane. Each cell contains a smooth-maxed interlocking scale SDF (a flattened, angled sphere or capped cone). The height and angle of each scale are displaced by a slow-moving FBM noise, simulating organic breathing. Below the scales lies a flat plane heavily distorted by domain warping to simulate turbulent plasma.

### Mouse Interaction
The mouse position (mapped to world space) creates a localized gravitational push, using `smoothstep` to calculate distance. Scales within this radius have their rotation angles flipped open, exposing the inner plasma layer.

### Color Mapping / Shading
Scales feature a dark, oily metallic material with thin-film interference (iridescent highlights based on the viewing angle and normal). The inner plasma layer is shaded with a blazing hot blackbody radiation gradient (deep red to bright cyan/white), pulsing intensely with `u.config.y`.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Abyssal Leviathan-Scales
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// --- UTILITY FUNCTIONS ---
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453); }
fn rot2D(a: f32) -> mat2x2<f32> { let c = cos(a); let s = sin(a); return mat2x2<f32>(c, -s, s, c); }

// --- SDF FUNCTIONS ---
fn sdScale(p: vec3<f32>, size: f32) -> f32 {
    return length(p) - size; // placeholder
}
fn map(p: vec3<f32>) -> vec2<f32> {
    // 1. Calculate hex grid cell and local pos
    // 2. Apply breathing FBM and mouse repulsion to scale rotation
    // 3. Evaluate scale SDF and underlying plasma SDF
    // 4. Return min distance and material ID
    return vec2<f32>(length(p) - 1.0, 1.0);
}

// --- RAYMARCHING & LIGHTING ---
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // Calculate UVs, setup camera, invoke render
    let uv = vec2<f32>(id.xy) / vec2<f32>(800.0, 600.0);
    let col = vec4<f32>(uv, 0.5, 1.0);
    textureStore(writeTexture, id.xy, col);
}
```

## Parameters (for UI sliders)

Name (default, min, max, step)
- Scale Density: `u.zoom_params.x` (default 5.0, min 1.0, max 15.0, step 0.1)
- Plasma Intensity: `u.zoom_params.y` (default 1.0, min 0.0, max 5.0, step 0.1)
- Breathing Speed: `u.zoom_params.z` (default 1.0, min 0.1, max 3.0, step 0.1)
- Core Heat: `u.zoom_params.w` (default 2.0, min 0.5, max 5.0, step 0.1)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
