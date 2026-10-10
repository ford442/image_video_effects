# New Shader Plan: Sentient Plasma-Silk Nebula Forge

## Overview
A hyper-dimensional nebula forge that weaves luminous, reactive threads of plasma silk around a cosmic spindle.

## Features
- Ethereal plasma-silk threads generated via domain warping and 3D noise (FBM).
- Central glowing energetic core representing the nebula forge spindle.
- Deep, multi-layered cosmic space background with volumetric fog.
- Reactive mouse interactions: acts as a gravity well, twisting threads around the cursor.
- Dynamic color shifts based on thread density, varying from hot pink to electric cyan.
- Smooth bloom achieved via temporal accumulation and tonemapping.

## Technical Implementation
- File: public/shaders/gen-sentient-plasma-silk-nebula-forge.wgsl
- Category: generative
- Tags: ["organic", "cosmic", "nebula", "plasma", "glow", "3d"]
- Algorithm: Raymarching an organic volumetric structure with complex domain warping and gravitational distortion.

### Core Algorithm
- Raymarching a signed distance field (SDF) composed of fractal lines (threads) and a central glowing sphere.
- Uses 3D noise (FBM) to apply domain warping to space, folding and twisting it.
- Threads are modeled as swirling vortexes mapped through multiple iterations of rotation `q.xy *= rot2D(time + distance)`.

### Mouse Interaction
- When `u.zoom_config.w > 0.0` (mouse down), the cursor acts as an active gravity well.
- The mouse position (`u.zoom_config.yz`) shifts the center of gravity and applies an intense local vortex distortion to the threads.
- Pull strength falls off exponentially with distance from the cursor.

### Color Mapping / Shading
- Base environment is deep purple/indigo `vec3(0.02, 0.0, 0.08)`.
- Threads use a cosine color palette driven by spatial position and iteration count, yielding cyan and magenta highlights.
- Ambient occlusion is estimated based on raymarching step count, creating deep shadows within the silk web.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Sentient Plasma-Silk Nebula Forge
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
  config: vec4<f32>,              // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,         // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,         // .xyzw = user params p1..p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// Helper: 2D Rotation
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Helper: Palette
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(TAU * (c * t + d + u.zoom_params.w));
}

// SDF
fn map(p: vec3<f32>) -> f32 {
    var q = p;
    let time = u.config.x * u.zoom_params.y;

    if (u.zoom_config.w > 0.0) {
        let mouse_pos = vec2<f32>(u.zoom_config.y - 0.5, (1.0 - u.zoom_config.z) - 0.5) * 5.0;
        let dist = length(q.xy - mouse_pos);
        let pull = exp(-dist * 2.0);
        let qxy = q.xy - mouse_pos * pull;
        q = vec3<f32>(qxy, q.z);
    }

    let rot = rot2D(time * 0.3 + length(q) * 0.4);
    let qxz = q.xz * rot;
    q = vec3<f32>(qxz.x, q.y, qxz.y);

    var d = 100.0;
    let density = u.zoom_params.x * 2.0 + 1.0;

    for (var i = 0; i < 4; i++) {
        let fi = f32(i);
        q = abs(q) - vec3<f32>(0.5) * density;
        let qr = q.xy * rot2D(time * 0.15 + fi);
        q = vec3<f32>(qr, q.z);
        let cyl = length(q.xy) - 0.06 * (fi + 1.0);
        d = min(d, cyl);
    }

    let sphere = length(p) - 0.9;

    let k = 0.5;
    let h = clamp(0.5 + 0.5 * (sphere - d) / k, 0.0, 1.0);
    return mix(sphere, d, h) - k * h * (1.0 - h);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // ... complete implementation ...
}
```
Parameters (for UI sliders)

Name (default, min, max, step)
- Silk Density (0.5, 0.0, 1.0, 0.01) -> zoom_params.x
- Spindle Speed (0.5, 0.0, 1.0, 0.01) -> zoom_params.y
- Core Glow (0.5, 0.0, 1.0, 0.01) -> zoom_params.z
- Color Shift (0.0, 0.0, 1.0, 0.01) -> zoom_params.w

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
