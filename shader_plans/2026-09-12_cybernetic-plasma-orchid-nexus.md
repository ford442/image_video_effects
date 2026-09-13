# New Shader Plan: Cybernetic Plasma-Orchid Nexus

## Overview
A hyper-stylized digital flora ecosystem where crystalline petals of plasma bloom from a glowing cybernetic core, pulsating with neon chromatic aberration.

## Features
- Dynamic petal unfolding driven by layered domain warping.
- Volumetric glowing plasma core utilizing sub-surface scattering approximations.
- Bioluminescent neon chromatic aberration along edge boundaries.
- Mouse-driven magnetic gravity well that distorts the orchid's symmetry.
- Audio-reactive temporal modulation for blooming speed and petal resonance.
- Procedural iridescence applied via normal mapping and Fresnel effects.

## Technical Implementation
- File: public/shaders/gen-cybernetic-plasma-orchid-nexus.wgsl
- Category: generative
- Tags: ["organic", "cybernetic", "floral", "plasma", "glow"]
- Algorithm: Raymarching SDFs with polar repetition and fractional Brownian motion for petal displacement.

### Core Algorithm
The architecture is centered around raymarching signed distance fields (SDFs). The central core is an intersecting sphere and torus with intense glowing properties. The orchid petals are modeled as thin SDF plates wrapped via polar repetition (`atan2(p.y, p.x)`) and bent outwards. The petals' surfaces are displaced using fractional Brownian motion (fBm) noise to create organic, rigid, yet fluid wrinkles characteristic of a cybernetic synthetic flower.

### Mouse Interaction
The user's mouse position determines the epicenter of a magnetic gravity well in 3D space. The raymarching coordinates (`p`) are displaced towards the mouse coordinate (`u.mouse.xy`), warping the polar repetition and breaking the perfect symmetry of the orchid petals. The distance to the mouse dictates the strength of the distortion via an inverse square law mapping.

### Color Mapping / Shading
Shading employs a synthetic Fresnel effect paired with a vibrant neon color palette. The core radiates bright cyan and magenta (mapped via `cos(p.z + time)` palette generation). The petals feature procedural iridescence—shifting from deep purples to golden yellows depending on the view angle. An intense multi-tap blur/bloom effect is integrated along with chromatic aberration separating the red and blue color channels near the edges of the petals.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Cybernetic Plasma-Orchid Nexus
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
    zoom_params: vec4<f32>,
    color_params: vec4<f32>,
    speed_params: vec4<f32>,
    extra_params: vec4<f32>,
}

// 2D Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Custom SDFs and Noise functions
// ...

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);

    if (coords.x >= i32(dimensions.x) || coords.y >= i32(dimensions.y)) {
        return;
    }

    let resolution = vec2<f32>(dimensions);
    var uv = (vec2<f32>(coords) + 0.5) / resolution;
    let base_uv = uv;
    uv = uv * 2.0 - 1.0;
    uv.x *= resolution.x / resolution.y;

    // Raymarching setup
    var ro = vec3<f32>(0.0, 0.0, -3.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Core raymarching loop
    // ...

    // Color mapping and shading
    // ...

    let final_color = vec4<f32>(0.0, 0.0, 0.0, 1.0); // Placeholder
    textureStore(writeTexture, coords, final_color);
}
```

## Parameters (for UI sliders)
- Petal Complexity (`zoom_params.x`, default: 3.0, min: 1.0, max: 8.0, step: 0.1)
- Plasma Intensity (`color_params.x`, default: 1.5, min: 0.1, max: 3.0, step: 0.1)
- Distortion Strength (`extra_params.x`, default: 0.5, min: 0.0, max: 2.0, step: 0.1)
- Bloom Spread (`color_params.y`, default: 0.8, min: 0.1, max: 2.0, step: 0.1)
- Rotation Speed (`speed_params.x`, default: 1.0, min: -2.0, max: 2.0, step: 0.1)
