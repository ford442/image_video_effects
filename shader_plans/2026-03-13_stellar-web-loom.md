# New Shader Plan: Stellar Web-Loom

## Overview
A hyper-dimensional cosmic loom weaving infinite tendrils of starlight and plasma silk across a dark void, blending organic neuro-network vibes with vast, mechanical astrophysics.

## Features
- Plasma Silk Threads: Delicate, branching volumetric lines that connect massive glowing cosmic nodes.
- Gravity-Bent Starlight: Real-time raymarching optical illusions where the dense nodes warp the threads of light passing near them.
- Audio-Spun Weaving: Beat detection (`u.config.y`) pulses energy through the plasma threads, accelerating the "weaving" animation along their length.
- Mouse Singularity: The cursor acts as a localized black hole, drawing the threads into a dense, swirling accretion disc.
- Deep Void Parallax: Layered, starry background noise providing immense depth behind the infinite repeating loom.

## Technical Implementation
- File: public/shaders/gen-stellar-web-loom.wgsl
- Category: generative
- Tags: ["cosmic", "neuro", "plasma", "volumetric", "audio-reactive"]
- Algorithm: Raymarching through domain repetition with heavy fbm-warped cylinder SDFs and distance-based glow accumulation.

### Core Algorithm
The scene uses infinite domain repetition (`opRep`) to scatter massive node anchors. The connections (silk threads) are modeled as `sdCylinder` primitives whose space coordinates (`p`) are fiercely displaced by 3D Fractional Brownian Motion (fbm). The combination creates twisted, branching pathways.

### Mouse Interaction
The `u.mouse` coordinates map to a 3D position in the raymarching space. An inverse-square gravity function is applied: as the ray `p` gets closer to the mouse, `p` is rotated and pulled toward the mouse origin before the SDFs are evaluated, twisting the silk threads into a whirlpool shape.

### Color Mapping / Shading
A purely additive volumetric approach is used. Instead of hard surface hits, the raymarcher accumulates glow based on how close the ray passes to the SDFs (`glow += 0.05 / (0.01 + abs(d))`). Colors range from deep violet to blinding stellar blue, pushed into hyper-luminosity by the `u.config.y` audio accumulator.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Stellar Web-Loom
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// SDF Primitives
// sdSphere (Nodes)
// sdCylinder (Plasma Threads)
// opRep (Infinite Lacing)

// Helpers
// rot2D
// fbm (3D noise for thread branching)

// Map Function
// - Warps domain based on fbm to twist cylinders
// - Calculates distance to nodes and threads
// - Applies mouse singularity distortion
// - Returns vec2(distance, material_id)

// Raymarching & Shading
// - Loops over steps, accumulating emissive glow
// - Injects color mapping based on thread density
// - Adds audio-reactive flares based on u.config.y

// Compute Shader Entry Point
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // 1. Ray setup and camera matrix
    // 2. Volumetric raymarching loop (accumulating color)
    // 3. Apply background parallax stars
    // 4. writeTexture update
}
```

## Parameters (for UI sliders)

Thread Density (2.0, 0.5, 5.0, 0.1)
Weave Speed (1.0, 0.0, 3.0, 0.1)
Plasma Glow (3.0, 1.0, 8.0, 0.1)
Singularity Pull (1.5, 0.0, 5.0, 0.1)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
