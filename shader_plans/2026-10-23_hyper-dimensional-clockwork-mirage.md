# New Shader Plan: Hyper-Dimensional Clockwork Mirage

## Overview
A mesmerizing, non-Euclidean clockwork mechanism where interlocking golden gears and holographic data streams emerge from an infinite, crystalline fractal void.

## Features
- Intricate SDF-based gear systems rotating on intersecting multidimensional planes.
- Iridescent, physically-based shading (PBR) approximations on metallic surfaces with chromatic aberration edges.
- Audio-reactive pulsing and structural morphing driven by plasmaBuffer.
- Dense volumetric fog and ray-marched bloom creating a cinematic atmosphere.
- Holographic, neon-glowing data rings intersecting the mechanical structure.
- Mouse-driven gravity well that bends and distorts the spatial coordinates of the gears.

## Technical Implementation
- File: public/shaders/gen-hyper-dimensional-clockwork-mirage.wgsl
- Category: generative
- Tags: ["clockwork", "fractal", "metallic", "hologram", "audio-reactive", "raymarching"]
- Algorithm: Raymarching against a complex scene of combined SDF primitives (cylinders, tori, boxes) with domain repetition and fractal folding, shaded with multi-light PBR and volumetric accumulation.

### Core Algorithm
- Uses sphere tracing/raymarching as the primary rendering technique.
- Employs domain repetition (modulo operations) to create infinite fields of mechanical parts.
- Uses rotational matrices and sinusoidal functions driven by `u.config.x` (time) to animate the interlocking gears.
- Integrates `plasmaBuffer[0]` (bass, mids, treble) to scale the fractal folding iterations and pulse the glowing elements.

### Mouse Interaction
- When `u.zoom_config.w > 0.5` (mouse clicked), the mouse position (`u.zoom_config.yz`) acts as a localized spatial black hole.
- The ray direction and spatial coordinates in the SDF evaluation are warped towards the mouse coordinates, applying an inverse-square distance distortion function.

### Color Mapping / Shading
- Primary structures use a metallic gold/brass shading approach, computing specular highlights with a Schlick approximation.
- Holographic rings use additive blending with neon cyan and magenta colors.
- Distance-based fog (volumetric atmospheric scattering) fades the distant machinery into a deep, crystalline void color (dark indigo/violet).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Hyper-Dimensional Clockwork Mirage
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

// ... (full skeleton with comments)
// fn sdGear(...) -> f32
// fn map(...) -> vec2<f32> // returns dist and material ID
// fn calcNormal(...) -> vec3<f32>
// fn render(...) -> vec4<f32>
// @compute @workgroup_size(16, 16) fn main(...)
```

Parameters (for UI sliders)

Complexity (0.5, 0.0, 1.0, 0.01)
Gear Speed (1.0, -2.0, 2.0, 0.1)
Glow Intensity (0.8, 0.0, 2.0, 0.05)
Fractal Fold (0.3, 0.0, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
