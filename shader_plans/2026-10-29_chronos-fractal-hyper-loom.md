# New Shader Plan: Chronos Fractal Hyper-Loom

## Overview
A hyper-dimensional weaving of time and light, where glowing ethereal threads intersect to form an infinitely shifting fractal tapestry.

## Features
- Ethereal glowing threads that pulse with celestial energy
- Infinite fractal zooming creating a sense of boundless scale
- Subsurface scattering simulation for a translucent, dream-like quality
- Audio-reactive ripples that disturb the delicate web of light
- Mouse-interactive gravity wells that warp the fractal topology
- Chromatic aberration at the fringes of the temporal weave

## Technical Implementation
- File: public/shaders/gen-chronos-fractal-hyper-loom.wgsl
- Category: generative
- Tags: ["fractal", "weaving", "time", "ethereal", "quantum"]
- Algorithm: Raymarched fractal noise fields combined with domain warping and iterative folding.

### Core Algorithm
Uses a 3D raymarching approach evaluating a complex Signed Distance Field (SDF). The geometry is generated using iterative fractal folding (similar to Mandelbox or Kali-set) intersected with domain-warped Voronoi noise to create the "threads". Audio data (`plasmaBuffer[0]`) modulates the folding parameters and the emission intensity of the threads.

### Mouse Interaction
The mouse (`u.zoom_config.yz`) creates a localized spatial distortion in the raymarching domain. When `u.zoom_config.w > 0.5` (mouse clicked), the space warps towards the mouse coordinate, creating a "gravity well" that pulls the fractal threads into a spiraling vortex.

### Color Mapping / Shading
Shading involves a base color determined by the accumulated distance along the ray (simulating volumetric depth) overlaid with vibrant, glowing gradients (cyan, magenta, gold). Subsurface scattering is approximated by blurring the depth accumulation and applying a color tint.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Chronos Fractal Hyper-Loom
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

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Fractal folding SDF
fn sdf_fractal(p: vec3<f32>, time: f32, scale: f32, bass: f32) -> f32 {
    var p_mod = p;
    var d = 1.0;
    for (var i = 0; i < 5; i++) {
        p_mod = abs(p_mod) - vec3<f32>(1.0 + bass * 0.2) * scale;

        var temp_xy = p_mod.xy;
        temp_xy = rot(time * 0.1 + f32(i)) * temp_xy;
        p_mod.x = temp_xy.x;
        p_mod.y = temp_xy.y;

        var temp_xz = p_mod.xz;
        temp_xz = rot(time * 0.15) * temp_xz;
        p_mod.x = temp_xz.x;
        p_mod.z = temp_xz.y;

        p_mod *= 1.5;
        d *= 1.5;
    }
    return (length(p_mod) - 0.5) / d;
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }
    let uv = vec2<f32>(id.xy) / resolution;
    let time = u.config.x;

    // Centered UV for raymarching
    var p = vec2<f32>(uv * 2.0 - 1.0);
    p.x *= resolution.x / resolution.y;

    // Audio Reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    // Mouse Interaction
    if (u.zoom_config.w > 0.5) {
        let mouse_uv_c = u.zoom_config.yz * 2.0 - 1.0;
        let mouse_dist = distance(p, mouse_uv_c);
        let warp_factor = smoothstep(0.8, 0.0, mouse_dist);
        p -= (p - mouse_uv_c) * warp_factor * u.zoom_params.y;
    }

    // Raymarching setup
    var ro = vec3<f32>(0.0, 0.0, -3.0);
    var rd = normalize(vec3<f32>(p, 1.0));

    var t = 0.0;
    var max_steps = 64;
    var d = 0.0;
    var p_current = ro;

    for (var i = 0; i < max_steps; i++) {
        p_current = ro + rd * t;
        d = sdf_fractal(p_current, time, u.zoom_params.x, bass);
        if (d < 0.001 || t > 10.0) { break; }
        t += d;
    }

    // Coloring
    var col = vec3<f32>(0.0);
    if (t < 10.0) {
        let depth_val = 1.0 - (t / 10.0);
        let glow = f32(max_steps) / 64.0;

        let color_shift = u.zoom_params.z;
        let bloom = u.zoom_params.w;

        col = vec3<f32>(
            sin(time * 0.5 + depth_val * 5.0 + color_shift) * 0.5 + 0.5,
            cos(time * 0.3 + depth_val * 3.0 + mids) * 0.5 + 0.5,
            sin(time * 0.7 + depth_val * 7.0 + treble) * 0.5 + 0.5
        ) * depth_val * bloom * glow;
    }

    let final_color = vec4<f32>(col, 1.0);
    textureStore(writeTexture, id.xy, final_color);
}
```
Parameters (for UI sliders)

Fractal Fold Scale (1.0, 0.1, 5.0, 0.1)
Gravity Well Strength (1.0, 0.0, 2.0, 0.1)
Color Shift (0.5, 0.0, 1.0, 0.01)
Bloom Intensity (1.5, 0.0, 3.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
