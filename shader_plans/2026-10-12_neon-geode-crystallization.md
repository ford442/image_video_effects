# New Shader Plan: Neon Geode Crystallization

## Overview
An endlessly shifting landscape of procedural bismuth-like crystals erupting with luminescent neon plasma, blending sharp geometry with fluid energy.

## Features
- Procedural crystal growth using recursive SDFs and domain repetition
- Multi-layered iridescent noise for chaotic energy rivers
- Subsurface scattering and neon bloom color mapping
- Fake ambient occlusion based on raymarch step counts
- Interactive geometric displacement driven by mouse gravity wells

## Technical Implementation
- File: public/shaders/gen-neon-geode-crystallization.wgsl
- Category: generative
- Tags: ["crystal", "neon", "geometric", "organic", "plasma"]
- Algorithm: Raymarching against folded/repeated SDF structures modulated by 3D simplex noise.

### Core Algorithm
Uses a raymarching loop with SDFs for sharp box folds and domain repetition (`fract` based) to create infinite crystalline structures. Noise functions distort the SDF surfaces to create organic plasma veins running through the geometry.

### Mouse Interaction
Gravity well: `u.zoom_config.w > 0.0` activates a distortion where rays bend towards `u.zoom_config.yz`, creating a localized melting or shattering effect on the crystals.

### Color Mapping / Shading
Base metallic shading based on surface normals. Iridescent gradients applied to the plasma veins based on SDF distance. Fake bloom accumulated through raymarching step count.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Neon Geode Crystallization
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
// ... (full skeleton with comments)

// Raymarching and SDF functions
fn map(p: vec3<f32>) -> f32 {
    // ... crystal SDF with folding and noise
    return 0.0;
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // ... standard compute shader skeleton ...
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Plasma Intensity (0.5, 0.0, 1.0, 0.01)
- Crystal Fold (1.0, 0.0, 5.0, 0.1)
- Bloom Radius (0.8, 0.1, 2.0, 0.01)
- Geometry Twist (0.0, -3.14, 3.14, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
