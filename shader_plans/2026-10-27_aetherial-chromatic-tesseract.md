# New Shader Plan: Aetherial Chromatic Tesseract

## Overview
A hyper-dimensional, endlessly folding geometry that catches and refracts iridescent, liquid-light gradients, reacting to sound and gravity.

## Features
- Intricate 4D-style Tesseract folding structures via SDF operations.
- Iridescent "thin-film" interference color mapping on surfaces.
- Audio-reactive structural expansion and contraction using plasmaBuffer.
- Mouse gravity wells that warp space-time around the cursor.
- Soft shadow tracing and ambient occlusion for deep geometric contrast.
- Subsurface scattering effect for a translucent, ethereal aesthetic.

## Technical Implementation
- File: public/shaders/gen-aetherial-chromatic-tesseract.wgsl
- Category: generative
- Tags: ["geometric", "4d", "iridescent", "audio-reactive", "interactive"]
- Algorithm: Raymarching with domain repetition, folding, and complex lighting functions.

### Core Algorithm
Raymarching an SDF that uses `opRep` (domain repetition) and fractal-like geometric folding (`abs()` and rotation matrices). The distance function defines a central hyper-cube that constantly shifts its internal faces. Audio bands (bass, mids, treble) modulate the scaling and rotation angles.

### Mouse Interaction
When `u.zoom_config.w > 0.5`, the mouse cursor `u.zoom_config.yz` acts as a gravity well. A smooth `length()` based falloff function distorts the raymarching coordinate space towards the mouse position, creating a localized warping effect.

### Color Mapping / Shading
Lighting calculates normals using the gradient of the SDF. The base color uses an iridescent palette (`cos(t + dot(n, v))`). Soft shadows and ambient occlusion add depth. A glow map is applied based on proximity to the central geometry and audio levels.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Aetherial Chromatic Tesseract
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

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(id.xy) / resolution;
    let time = u.config.x;

    // Audio Reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);

    // Mouse Interaction
    var warp = vec2<f32>(0.0);
    if (u.zoom_config.w > 0.5) {
        let mouse_uv = u.zoom_config.yz;
        let dist = length(uv - mouse_uv);
        warp = normalize(uv - mouse_uv) * exp(-dist * 5.0) * 0.1;
    }

    let p = uv + warp;

    // Placeholder Raymarching loop and color calc
    let col = vec3<f32>(0.5 + 0.5 * cos(time + p.xyx + vec3<f32>(0, 2, 4))) * (1.0 + bass * 0.5);

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}
```
Parameters (for UI sliders)

Fold Complexity (1.0, 0.1, 5.0, 0.1)
Iridescence Shift (0.5, 0.0, 1.0, 0.01)
Gravity Strength (1.0, 0.0, 3.0, 0.1)
Glow Intensity (1.0, 0.0, 2.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
