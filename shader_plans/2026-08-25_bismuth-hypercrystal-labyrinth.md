# New Shader Plan: Bismuth Hypercrystal Labyrinth

## Overview
A mesmerizing, iridescent raymarched journey through procedurally generated, self-similar crystalline structures that evolve over time, resembling natural bismuth hopper crystals on a cosmic scale.

## Features
- Intricate, multi-layered SDF geometries forming infinite hopper-crystal patterns.
- Iridescent "bismuth" thin-film interference shading with vibrant, shifting metallic color palettes.
- Audio-reactive crystal growth and pulse effects (bound to low and mid frequencies).
- Gravity-well mouse interactions that distort the crystal lattice like a spacetime anomaly.
- Soft shadows, ambient occlusion, and intense glowing core effects for dramatic lighting.
- Multi-pass temporal accumulation for smooth, anti-aliased hyper-detail.

## Technical Implementation
- File: public/shaders/gen-bismuth-hypercrystal-labyrinth.wgsl
- Category: generative
- Tags: ["3d", "raymarching", "bismuth", "crystal", "iridescent", "fractal", "audio-reactive"]
- Algorithm: Raymarching infinite domains with folded SDFs and thin-film color interference approximations.

### Core Algorithm
- Uses `opRep` (domain repetition) and fractal space folding (like Menger sponge iterations) to create the tiered, stepped "hopper" crystal look characteristic of Bismuth.
- A custom SDF combines boxes and cross shapes, iteratively rotated and scaled down.
- Audio-reactive scaling (sampling `dataTextureC`) modulates the step size and rotation angles, making the structure "breathe" with the music.

### Mouse Interaction
- The mouse position acts as a localized distortion field.
- We use a smoothstep falloff based on the distance from the ray origin/hit point to a target derived from `u.zoom_config.yz`.
- Inside the gravity well, space is twisted along the Z-axis, warping the rigid crystal geometry into a spiral.

### Color Mapping / Shading
- Instead of standard diffuse/specular, we use a custom thin-film interference approximation based on the viewing angle (dot product of normal and view direction) combined with the SDF distance or fractal iteration count.
- This creates the signature vibrant, rainbow-like metallic sheen of Bismuth.
- Added a bloom pass (or simple distance-based glow accumulated during raymarching) to make deep crevices emit ethereal light.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Bismuth Hypercrystal Labyrinth
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
  zoom_params: vec4<f32>,  // .x = Complexity, .y = Color Shift, .z = Glow Intensity, .w = Twist
  ripples: array<vec4<f32>, 50>,
};

// ... constants and helpers

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ... SDF functions ...

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // ... Raymarching setup ...
    // ... Audio reactivity sampling ...
    // ... Mouse interaction twisting ...
    // ... Shading ...
    // ... Store to writeTexture ...
}
```

Parameters (for UI sliders)
Complexity (1.0, 0.1, 5.0, 0.1)
Color Shift (0.5, 0.0, 1.0, 0.01)
Glow Intensity (1.5, 0.0, 5.0, 0.1)
Twist (0.0, -2.0, 2.0, 0.1)
