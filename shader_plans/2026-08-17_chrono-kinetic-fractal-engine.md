# New Shader Plan: Chrono-Kinetic Fractal Engine

## Overview
A highly dynamic, continuously unfolding 4D mechanism where temporal gears and non-euclidean clockwork structures weave together into an infinite, hypnotic mandala of light and motion.

## Features
- Intricate 4D non-euclidean space folding for endless recursion.
- Procedural temporal-gear SDFs driven by fractional time variations.
- Iridescent metallic shading with deep chromatic aberration and internal reflections.
- Gravitational "time-dilation" mouse interaction that warps and bends the local space-time fabric.
- Audio-reactive kinetic bursts that shatter and seamlessly reform the crystalline mechanism.

## Technical Implementation
- File: public/shaders/gen-chrono-kinetic-fractal-engine.wgsl
- Category: generative
- Tags: ["fractal", "kinetic", "4d", "iridescent", "clockwork"]
- Algorithm: Raymarching through domain-repeated and 4D-rotated geometric primitives, employing complex SDF boolean operations and orbit traps for intricate texturing.

### Core Algorithm
The core utilizes a spherical raymarching engine. Space is domain-repeated using `p = (p % spacing) - spacing * 0.5`. Inside the repeated space, multi-axis 4D rotations (XW, YZ planes) are applied based on `u.config.x` (time). The primitive is a blend of a Torus and an Octahedron, with recursive Menger-like folding to create intricate 'clockwork' cutouts. Orbit traps accumulate distance fields over iterations to generate deep coloring.

### Mouse Interaction
The mouse (`u.zoom_config.y`, `u.zoom_config.z`) establishes a gravity well in the center of the screen. As the mouse moves, a radial distance function distorts the spatial coordinates (`p`), applying a non-linear twist (a "time-dilation" warp) that spirals the fractal towards the cursor position.

### Color Mapping / Shading
The shading utilizes a physically-based approach approximating iridescent metallic surfaces. It calculates normals using the tetrahedron technique. The base color is mapped from the orbit trap accumulation using a cosine-based palette. A simulated chromatic aberration is added by sampling slightly offset ray directions for R, G, and B channels, combined with a bright neon bloom mask.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Chrono-Kinetic Fractal Engine
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
  zoom_params: vec4<f32>,  // .x = Point Density, .y = Rotation Speed, .z = Point Size, .w = Color Shift
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265;
const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;

// ... Distance Functions ...
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * h * k * (1.0 / 6.0);
}

fn map(p: vec3<f32>) -> vec2<f32> {
    // Spatial folding and domain repetition logic
    var pos = p;
    // Apply mouse warping
    // Return distance and material ID
    return vec2<f32>(length(pos) - 1.0, 1.0);
}

// ... Lighting and Normals ...
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(e.xyy * map(p + e.xyy).x +
                     e.yyx * map(p + e.yyx).x +
                     e.yxy * map(p + e.yxy).x +
                     e.xxx * map(p + e.xxx).x);
}

// ... Main Render Loop ...
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // Setup UVs, Ray Origin, Ray Direction
    // Raymarching loop
    // Shading and Color Mapping
    // Write to texture
}
```

## Parameters (for UI sliders)

Complexity (1.0, 0.1, 5.0, 0.1) -> Mapped to u.zoom_params.x
Warp Strength (0.5, 0.0, 2.0, 0.01) -> Mapped to u.zoom_params.y
Iridescence (1.0, 0.0, 3.0, 0.1) -> Mapped to u.zoom_params.z
Kinetic Speed (1.0, 0.1, 3.0, 0.1) -> Mapped to u.zoom_params.w

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
