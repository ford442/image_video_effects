# New Shader Plan: Sentient Bismuth Hypercrystal

## Overview
A slowly mutating, infinitely folding iridiscent bismuth hopper crystal that visually pulses and geometrically adapts to the user's audio frequency and mouse presence, creating a feeling of a living alien artifact.

## Features
- Real-time audio reactive geometry deformation and growth
- Iridescent, physically-based thin-film interference coloring
- Infinite geometric folding via domain repetition and complex SDF operations
- "Gravity well" mouse interaction that bends the crystalline structure
- Dynamic, shifting lighting environment simulating an alien nebula
- Temporal anti-aliasing (TAA) and subtle bloom for cinematic presentation

## Technical Implementation
- File: public/shaders/gen-sentient-bismuth-hypercrystal.wgsl
- Category: generative
- Tags: ["3d", "sdf", "raymarching", "bismuth", "iridescent", "audio-reactive", "interactive"]
- Algorithm: Raymarching against a complex folded Signed Distance Field (SDF). The geometry uses recursive box folding (Menger sponge variations) mapped with domain repetition. Thin film interference color mapping based on normal incidence and depth.

### Core Algorithm
The core uses raymarching over a recursive SDF. The base shape is a cuboid. The space is folded iteratively using absolute value mirroring (`abs(p) - offset`) combined with rotation matrices to create the characteristic "hopper crystal" terraced growth of bismuth. To give it life, the folding offsets and rotation angles are modulated by low-frequency noise (for slow breathing) and the audio input (sampled from `dataTextureC`).

### Mouse Interaction
The mouse acts as a localized spatial distortion field (a "gravity well"). We calculate the distance from the ray position to the mouse's projected 3D coordinate. Within a certain radius, space is warped (e.g., twisting or pinching), physically dragging and bending the straight crystalline edges into curves.

### Color Mapping / Shading
Instead of standard diffuse coloring, the shading relies on a thin-film interference approximation. The color is derived from a dot product of the surface normal and the view direction (`dot(N, V)`), mapped through a cosine palette to simulate varying film thickness. Audio reactivity further modulates this "thickness", causing flashes of specific colors (like vivid gold or magenta) on musical peaks.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Sentient Bismuth Hypercrystal
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
  zoom_params: vec4<f32>,  // .x = Growth, .y = Audio React, .z = Twist, .w = Iridescence
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;

// 1. Rotation Matrix Helper
fn rot(a: f32) -> mat2x2<f32> { ... }

// 2. Map Function (SDF)
fn map(p: vec3<f32>, time: f32, audio: f32) -> f32 { ... }

// 3. Normal Calculation
fn getNormal(p: vec3<f32>, time: f32, audio: f32) -> vec3<f32> { ... }

// 4. Color / Iridescence Mapping
fn palette(t: f32) -> vec3<f32> { ... }

// 5. Main Compute Entry Point
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) { ... }
```

## Parameters (for UI sliders)
- Growth (1.0, 0.1, 5.0, 0.1)
- Audio React (1.0, 0.0, 3.0, 0.1)
- Twist (0.0, -2.0, 2.0, 0.1)
- Iridescence (1.0, 0.5, 3.0, 0.1)
