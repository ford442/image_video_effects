# New Shader Plan: Sonoluminescent Chrono-Geode Matrix

## Overview
A colossal, infinitely shattering crystalline geode that fractures to reveal a violently erupting sonoluminescent plasma core, with metallic shards levitating and reassembling in a slow-motion temporal loop.

## Features
- 4D KIFS (Kaleidoscopic Iterated Function System) fractal crystalline shell
- Fluid sonoluminescent plasma core using volumetric raymarching
- Audio-reactive shard shattering and levitation mechanics
- Slow-motion temporal reversal ("chrono") visual feedback loop
- Thin-film iridescent interference on the crystalline surfaces
- Interactive gravity well: mouse click repels shards and exposes the core

## Technical Implementation
- File: public/shaders/gen-sonoluminescent-chrono-geode-matrix.wgsl
- Category: generative
- Tags: ["geode", "plasma", "fractal", "temporal", "audio-reactive"]
- Algorithm: Volumetric raymarching of a domain-repeated KIFS fractal intersected with a smooth SDF sphere (the core), modified by 3D noise for the plasma.

### Core Algorithm
The scene is raymarched. The outer shell uses a folded KIFS fractal wrapped around a spherical domain. The inner core uses an SDF sphere heavily distorted by fBM 3D noise. The distance field smoothly interpolates between the hard crystal and the soft plasma based on a noise field driven by ambient audio energy.

### Mouse Interaction
When `u.zoom_config.w` (mouse down) is active, a repulsive force is applied at the mouse coordinates `u.zoom_config.xy`. This pushes the SDF boundaries of the crystalline shards outward radially, effectively "cracking" the geode wide open to reveal the bright plasma core inside.

### Color Mapping / Shading
The crystalline shell uses physically based rendering approximations: normal mapping, Fresnel reflections, and a custom iridescence lookup for a metallic bismuth-like finish. The plasma core uses additive blending in the raymarching loop with high-intensity neon colors mapped from ambient energy, creating a blinding, glowing effect.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Sonoluminescent Chrono-Geode Matrix
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// --- UTILITY FUNCTIONS ---
// (noise3D, rotation matrices, etc.)

// --- SDF SCENE ---
// (KIFS fractal folds, core sphere distance)

// --- RAYMARCHING ---
// (volumetric accumulation, normals, shading)

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // 1) Setup UVs and camera ray
    // 2) Apply mouse interaction to warp ray/space
    // 3) Raymarch scene (accumulate plasma glow + find crystal surface)
    // 4) Apply iridescent shading to crystal
    // 5) Mix colors and write to writeTexture
}
```

## Parameters (for UI sliders)

Name (default, min, max, step)
- Fracture Intensity (0.5, 0.0, 1.0, 0.01)
- Core Glow (2.0, 0.1, 5.0, 0.1)
- Geode Rotation (1.0, -3.0, 3.0, 0.1)
- Temporal Shift (0.5, 0.0, 1.0, 0.01)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
