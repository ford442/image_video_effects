# New Shader Plan: Synthetic Bismuth Geode Matrix

## Overview
A hyper-structured, iridescent crystal labyrinth that continuously grows and folds back onto itself in impossible non-Euclidean angles, capturing the rigid yet chaotic beauty of grown bismuth.

## Features
- Intricate, right-angled fractal generation using multi-octave box-folding SDFs
- Oil-slick iridescence color mapping based on surface normal variation and depth
- Temporal crystalline growth/recession driven by global time
- Specular "glitch" highlights that snap along major geometric axes
- Ambient occlusion approximations for deep structural shadows
- Mouse-driven gravity distortion that bends the normally rigid orthogonal structures
- Fluid transition between smooth glassy surfaces and hard metallic edges

## Technical Implementation
- File: public/shaders/gen-synthetic-bismuth-geode-matrix.wgsl
- Category: generative
- Tags: ["crystal", "fractal", "geometric", "iridescent", "raymarching"]
- Algorithm: Raymarching an orthogonally folded space (Menger/Box fractal variants) with temporal scaling and normal-based interference coloring.

### Core Algorithm
The space is folded repeatedly using absolute value and max() operations to create infinite right-angled corridors and terraces (box folding). The scale is driven by a chaotic oscillator so the geometry appears to extrude and crystallize over time. A standard raymarching loop will find the surface intersection.

### Mouse Interaction
The mouse creates a localized spatial warp. Instead of simple gravity, it acts as a magnetic singularity that applies a rotational twist (using a 2D rotation matrix based on distance to the mouse in screen/world space) to the rays before they enter the folding space, causing the rigid structures to warp into curved anomalies.

### Color Mapping / Shading
The coloring will mimic thin-film interference. By taking the dot product of the surface normal and the view ray, and passing the result through a cosine palette, we achieve the signature shifting neon pink/green/gold of bismuth. Sharp normals cause sharp color transitions.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Synthetic Bismuth Geode Matrix
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
  zoom_params: vec4<f32>,  // .x = Structural Complexity, .y = Iridescence Frequency, .z = Growth Speed, .w = Twist Intensity
  ripples: array<vec4<f32>, 50>,
};

// ... Constants and Helpers ...

// 2D Rotation function
fn rot2d(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Bismuth SDF Folding Space
fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;
    // Mouse twist
    let mouse_pos = (u.zoom_config.yz - vec2<f32>(0.5)) * 2.0;
    let dist_to_mouse = length(p.xy - mouse_pos);
    let twist = exp(-dist_to_mouse * 2.0) * u.zoom_params.w * 3.0 * u.zoom_config.w;

    // Rotate xy based on distance to mouse
    let s = sin(twist);
    let c = cos(twist);
    p = vec3<f32>(p.x * c - p.y * s, p.x * s + p.y * c, p.z);

    // Growth over time
    let time = u.config.x * u.zoom_params.z;
    var scale = 1.0;

    // Orthogonal folding iterations
    for (var i = 0; i < i32(u.zoom_params.x * 6.0); i++) {
        p = abs(p) - vec3<f32>(0.5 + sin(time * 0.1) * 0.1);

        // Menger/Box style fold
        if (p.x < p.y) { p = vec3<f32>(p.y, p.x, p.z); }
        if (p.x < p.z) { p = vec3<f32>(p.z, p.y, p.x); }
        if (p.y < p.z) { p = vec3<f32>(p.x, p.z, p.y); }

        p = p * 1.5 - vec3<f32>(1.0);
        scale *= 1.5;
    }

    // Box SDF
    let d = length(max(abs(p) - vec3<f32>(1.0), vec3<f32>(0.0))) + min(max(p.x, max(p.y, p.z)) - 1.0, 0.0);
    return d / scale;
}

// Normal Calculation ...
// Palette Calculation for Iridescence ...
// Main compute shader block ...
```

Parameters (for UI sliders)

Structural Complexity (default: 0.8, min: 0.1, max: 1.0, step: 0.05)
Iridescence Frequency (default: 2.0, min: 0.5, max: 5.0, step: 0.1)
Growth Speed (default: 1.0, min: 0.0, max: 3.0, step: 0.1)
Twist Intensity (default: 1.0, min: 0.0, max: 5.0, step: 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
