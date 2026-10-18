# New Shader Plan: Biomechanical Neural Mycelium

## Overview
A pulsing, subterranean network of glowing bio-metallic fibers that autonomously reconnect and twitch with synthetic intelligence.

## Features
- Intricate volumetric web generated via heavily iterated 3D fractional brownian motion.
- Bio-metallic surface rendering with high specularity and ambient occlusion based on step count.
- Glowing energy pulses traversing the fibers, simulated via time-offset thresholding.
- Mouse interaction: Drags the network space, stretching and distorting the mycelial connections toward the cursor.
- Acid-green to electric-blue color shifting across depths.
- Depth-based shadow rendering and fog for intense scale.

## Technical Implementation
- File: public/shaders/gen-biomechanical-neural-mycelium.wgsl
- Category: generative
- Tags: ["organic", "mechanical", "network", "glow", "fractal", "3d"]
- Algorithm: Raymarching through a dense lattice generated via multi-scale SDF operations (spheres, cylinders, smooth-min) warped by domain repetition.

### Core Algorithm
- Base structure is an infinite domain repetition of spheres (`opRep`) connected by thin cylinders.
- Domain is aggressively distorted using multiple layers of `sin`/`cos` (FBM) mapped to world coordinates.
- "Glow" is accumulated along the ray path, mapped to distance from the nearest fiber and modulated by `sin(time * speed + length(p))`.

### Mouse Interaction
- `zoom_config.w > 0.0` triggers active interaction.
- World coordinates (`p.xy`) are aggressively pulled toward `mouse_pos` with a distortion function `pull = exp(-length(p.xy - mouse_pos) * 3.0)`.

### Color Mapping / Shading
- Bio-metallic specular highlights calculated from normal mapping of the SDF gradient.
- Emissive glow maps calculated during raymarching (accumulation).
- Fake ambient occlusion (AO) derived from the number of raymarching steps taken to hit the surface.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Biomechanical Neural Mycelium
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

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(p: vec3<f32>) -> f32 {
    var q = p;
    let time = u.config.x * u.zoom_params.y;

    if (u.zoom_config.w > 0.0) {
        let mouse_pos = vec2<f32>(u.zoom_config.y - 0.5, (1.0 - u.zoom_config.z) - 0.5) * 5.0;
        let dist = length(q.xy - mouse_pos);
        let pull = exp(-dist * 3.0);
        let qxy = q.xy - mouse_pos * pull;
        q = vec3<f32>(qxy, q.z);
    }

    let rot = rot2D(time * 0.1 + q.z * 0.1);
    let qxy2 = q.xy * rot;
    q = vec3<f32>(qxy2.x, qxy2.y, q.z);

    let scale = u.zoom_params.x * 2.0 + 1.0;

    // Domain repetition
    var qRep = q;
    qRep.x = (fract(qRep.x / scale + 0.5) - 0.5) * scale;
    qRep.y = (fract(qRep.y / scale + 0.5) - 0.5) * scale;
    qRep.z = (fract(qRep.z / scale + 0.5) - 0.5) * scale;

    var d = length(qRep) - 0.1; // Spheres at nodes

    // Fibers
    var d2 = length(qRep.xy) - 0.02; // Z-axis fibers
    d2 = min(d2, length(qRep.xz) - 0.02); // Y-axis fibers
    d2 = min(d2, length(qRep.yz) - 0.02); // X-axis fibers

    d = smin(d, d2, 0.2);

    // Noise distortion
    d += sin(q.x * 5.0 + time) * cos(q.y * 4.0 - time) * 0.05;

    return d;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // ... compute implementation ...
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Network Density (0.5, 0.0, 1.0, 0.01) -> zoom_params.x
- Pulse Speed (0.5, 0.0, 1.0, 0.01) -> zoom_params.y
- Glow Intensity (0.5, 0.0, 1.0, 0.01) -> zoom_params.z
- Mycelium Color (0.0, 0.0, 1.0, 0.01) -> zoom_params.w

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
