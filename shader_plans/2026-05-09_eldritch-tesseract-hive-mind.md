# New Shader Plan: Eldritch Tesseract-Hive Mind

## Overview
An impossible, non-Euclidean hypercube hive populated by swarms of luminescent algorithmic sentinels, constantly unfolding and fracturing into new geometric dimensions driven by quantum noise and acoustic energy.

## Features
- **4D Hypercube Projection**: A continuously rotating tesseract structure folded down into 3D, creating interlocking, impossible geometric corridors.
- **Algorithmic Sentinel Swarms**: Millions of microscopic light-entities flow through the tesseract's veins like a circulatory system of raw data.
- **Voxelized Reality-Tearing**: Intense audio frequencies cause the smooth metallic geometry to fracture into chaotic, glowing volumetric voxels.
- **Iridescent Quantum-Slick Surfaces**: The struts of the hive reflect light like an abyssal oil slick, shifting colors through complex interference patterns.
- **Gravitational Anomalies**: Mouse interaction bends the local spacetime, creating gravitational lenses that distort both the geometry and the particle flows.

## Technical Implementation
- File: public/shaders/gen-eldritch-tesseract-hive-mind.wgsl
- Category: generative
- Tags: ["tesseract", "fractal", "quantum", "mechanical", "audio-reactive", "swarm"]
- Algorithm: Raymarching a true 4D SDF projection using multi-dimensional rotation matrices. The structure is modified by a 3D cellular noise function to carve out the "veins". The particles are simulated using a fractional Brownian motion (fBm) flow field constrained to the surface of the SDF.

### Core Algorithm
- **4D to 3D Projection**: Use a 4D distance estimator, iterating through a sequence of 4D rotation matrices (using XY, XZ, XW, YZ, YW, ZW planes). The coordinates are projected back to 3D space.
- **Boolean Carving**: Subtract 3D Voronoi noise from the tesseract edges to create the organic, hollowed-out look of the hive.
- **Voxel Tearing**: Modulate the coordinate space by `floor(p * voxelSize) / voxelSize` where `voxelSize` is driven by the audio spectrum, creating a snapping, glitchy voxelization effect on bass hits.

### Mouse Interaction
- The mouse position dynamically adjusts the 4W dimension of the hypercube and acts as a localized gravity well, sucking the structural veins and particle paths towards the cursor using an inverse-square distance falloff.

### Color Mapping / Shading
- The surface uses a thin-film interference approximation based on the viewing angle and the SDF normal. The "veins" emit a piercing, neon-cyan to magenta glow sampled from the `plasmaBuffer`, layered with intense additive bloom.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Eldritch Tesseract-Hive Mind
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>
};

// --- CONSTANTS & HELPERS ---
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

// 4D Rotation matrix helper
fn rot4D(theta: f32) -> mat2x2<f32> {
    let c = cos(theta);
    let s = sin(theta);
    return mat2x2<f32>(c, -s, s, c);
}

// Map function evaluating the 4D Tesseract SDF
fn map(p: vec3<f32>, time: f32, audio_intensity: f32) -> vec2<f32> {
    // 4D coordinate initialization
    var p4 = vec4<f32>(p, 0.0);

    // Rotate in 4D space
    let r1 = rot4D(time * 0.5);
    let x_new = r1[0][0]*p4.x + r1[0][1]*p4.z;
    let z_new = r1[1][0]*p4.x + r1[1][1]*p4.z;
    p4.x = x_new;
    p4.z = z_new;

    // Core tesseract SDF evaluation
    let d1 = length(max(abs(p4) - vec4<f32>(1.0), vec4<f32>(0.0))) - 0.1;

    // Add voxel tearing based on audio
    let voxel_scale = vec3<f32>(10.0 + audio_intensity * 20.0);
    let voxel_p = floor(p * voxel_scale) / voxel_scale;
    let d2 = length(p - voxel_p) - 0.05;

    // Material ID mix
    return vec2<f32>(min(d1, d2), 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // 1) Initialize UVs and Camera
    // 2) Raymarch the 4D environment
    // 3) Calculate thin-film interference for shading
    // 4) Add glowing sentinel swarms (via overlaid flow field)
    // 5) Write out final color
}
```

## Parameters (for UI sliders)

Name (default, min, max, step)
- Tesseract Rotation Speed (0.5, 0.0, 2.0, 0.01)
- Swarm Density (1.0, 0.1, 5.0, 0.1)
- Voxel Tearing Intensity (0.5, 0.0, 2.0, 0.05)
- Iridescence Shift (0.5, 0.0, 1.0, 0.01)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
