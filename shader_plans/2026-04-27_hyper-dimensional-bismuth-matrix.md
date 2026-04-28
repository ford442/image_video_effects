# New Shader Plan: Hyper-Dimensional Bismuth-Matrix

## Overview
An infinite, procedurally growing expanse of hyper-dimensional bismuth crystals, forming intricate, stair-stepped geometric fractals that shimmer with iridescent interference patterns and warp dynamically to audio frequencies.

## Features
- Procedurally generated, stair-stepped crystalline structures using infinite domain repetition and KIFS fractals.
- Vibrant, iridescent thin-film interference coloring mapped to surface normals and audio intensity.
- Extruding and shifting geometric formations that grow and retract to the rhythm of unseen bass frequencies.
- Ethereal, volumetrically glowing fog that settles in the deep, abyssal chasms between crystal peaks.
- Glass-like refractive edges and specular highlights mimicking metallic bismuth.
- Mouse interaction that acts as a localized quantum disruption field, scattering and reorganizing nearby crystal growth.

## Technical Implementation
- File: public/shaders/gen-hyper-dimensional-bismuth-matrix.wgsl
- Category: generative
- Tags: ["bismuth", "crystal", "iridescent", "fractal", "audio-reactive"]
- Algorithm: Raymarching infinite domains with KIFS (Kaleidoscopic Iterated Function Systems) and box-based SDFs (Signed Distance Fields) modified by step-functions to create sharp, cubic extrusions.

### Core Algorithm
- Primary geometry utilizes an SDF for an infinite grid of intersecting, rotating boxes.
- A stepping function (like `floor` or `round`) is applied to the spatial domain before the SDF to create the iconic "hopper crystal" stair-step look characteristic of bismuth.
- Domain repetition combined with rotation matrices driven by time and audio creates a massive, infinitely complex crystal cavern.
- Normal calculation incorporates high-frequency noise to simulate micro-facets on the crystal surfaces.

### Mouse Interaction
- The mouse coordinates (`u.mouse`) introduce a spherical distortion field.
- When the raymarched position falls within this field, the spatial coordinates are twisted and the step-size of the crystal formations becomes erratic, simulating a localized disruption in the crystallization process.

### Color Mapping / Shading
- The color palette heavily relies on an iridescent color ramp function `cos(t + vec3(0, 2, 4))` mapped to the dot product of the surface normal and the view direction, simulating thin-film interference.
- Intense, vibrant hues (pink, cyan, gold) that shift rapidly based on the audio frequency uniform.
- Depth-based fog and ambient occlusion to emphasize the massive scale of the structures.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Hyper-Dimensional Bismuth-Matrix
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    resolution: vec2<f32>,
    mouse: vec2<f32>,
    time: f32,
    frame: u32,
    config: vec4<f32>, // x: unused, y: audio, z: unused, w: unused
    zoom_params: vec4<f32>, // mapped to UI sliders
};

// ... Helper functions (rotations, smin, noise)

// ... SDF for stair-stepped hopper crystal
fn map(p: vec3<f32>) -> f32 {
    // Spatial distortion and domain repetition
    // Step function applied for bismuth structure
    // return distance
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.resolution.x) || global_id.y >= u32(u.resolution.y)) { return; }
    // Raymarching loop, shading, and iridescence mapping
    // Write output to writeTexture
}
```

Parameters (for UI sliders)

- Crystal Complexity (0.5, 0.1, 1.0, 0.01)
- Iridescence Shift (0.5, 0.0, 1.0, 0.01)
- Growth Rate (0.3, 0.0, 1.0, 0.01)
- Disruption Radius (0.2, 0.0, 1.0, 0.01)

Integration Steps

- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
