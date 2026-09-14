# New Shader Plan: Symbiotic Bismuth-Crystal Dragon-Core

## Overview
A hyper-intricate, continuously folding bismuth fractal labyrinth that breathes and pulses like a colossal, ancient techno-organic heart core. The aesthetic is a fusion of rigid, iridescent crystalline step-structures (bismuth) growing symbiotically over fluid, viscous liquid-gold organic sinews.

## Features
- Infinite zooming, folding 3D geometric step-fractals utilizing modulo-repetition and domain twisting.
- Iridescent "bismuth" color mapping with shifting, pearlescent specular highlights based on normal alignment and view angle.
- Breathing animation: the underlying domain space dilates and contracts on a slow, resonant frequency.
- Interactive mouse core: the center of gravity shifts towards the mouse, pulling the crystalline structures into a dense, bright singularity.
- Liquid-gold subsurface sinews that snake between the rigid crystal formations, glowing with a deep, volcanic warmth.
- High-frequency micro-displacement on the crystal faces to simulate microscopic fracture networks.
- Ambient occlusion emulation via raymarching step accumulation to deeply shadow the labyrinthine crevices.

## Technical Implementation
- File: public/shaders/gen-symbiotic-bismuth-dragon-core.wgsl
- Category: generative
- Tags: ["fractal", "bismuth", "crystal", "organic", "3d", "raymarching", "iridescent"]
- Algorithm: 3D Raymarching with recursive folded SDFs, modulo space repetition, and view-dependent interference color mapping.

### Core Algorithm
The base SDF is an intersected combination of a folded menger-like sponge and a domain-repeated cubic lattice. The space is repeatedly folded using `abs()` and rotated using `mat2x2` matrices driven by `u.config.x` (time). To create the "stepped" bismuth look, the distance field incorporates a `floor()` function or stepped domain modulation (`mod` with a discrete step size) mixed smoothly with continuous noise. The organic sinews are a separate, smooth SDF (`sdCapsule` or volumetric noise) subtracted or blended (`smin`) with the rigid crystals.

### Mouse Interaction
The mouse (`u.zoom_config.y`, `u.zoom_config.z`) dictates the location of a volumetric gravity well. As rays traverse the space, the origin of the domain is distorted (`p -= mouse_pos * strength / length(p - mouse_pos)`) before being fed into the fractal fold, causing the crystals to densely pack and warp towards the cursor. The "zoom" level can be modulated by `u.zoom_params.x`.

### Color Mapping / Shading
Bismuth iridescence is achieved by calculating the surface normal and mapping the dot product of the normal and the view direction (`dot(n, v)`) through a multi-frequency cosine palette (`cos(a + b*t + c*t^2)`). The liquid-gold sinews use a simpler, high-specular metallic PBR-style shading model with deep orange/red emission. Soft shadows and ambient occlusion are accumulated during the raymarching steps, heavily darkening deep crevices.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Symbiotic Bismuth-Crystal Dragon-Core
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
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // .xyzw = user params p1..p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

// ... (Constants, rotation matrices, palette functions)

// Map function returning vec2: .x = distance, .y = material ID (0 = crystal, 1 = sinew)
fn map(p: vec3<f32>) -> vec2<f32> {
    // Domain distortion (mouse)
    // Breathing scale
    // Fractal folds and stepped modulos for Bismuth
    // Smooth volumetric noise for Sinews
    // Return smin / union of materials
    return vec2<f32>(1.0, 0.0); // Placeholder
}

// Raymarch loop
// Normal calculation
// Shading (Iridescence vs Metallic Gold)

@compute @workgroup_size(16, 16, 1)
fn main_compute(@builtin(global_invocation_id) gid: vec3<u32>) {
    // Setup camera, ray direction, loop march, calculate lighting, store pixel
}
```

Parameters (for UI sliders)

Zoom (default 1.0, min 0.1, max 5.0, step 0.1) - mapped to zoom_params.x
Complexity (default 3.0, min 1.0, max 8.0, step 1.0) - mapped to zoom_params.y
Breathing Speed (default 0.5, min 0.0, max 2.0, step 0.1) - mapped to zoom_params.z
Iridescence Shift (default 0.0, min -3.14, max 3.14, step 0.01) - mapped to zoom_params.w
