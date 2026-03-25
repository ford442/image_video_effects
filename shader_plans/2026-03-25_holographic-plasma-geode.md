# New Shader Plan: Holographic Plasma-Geode

## Overview
A hyper-dimensional geode cracked open to reveal a swirling, audio-reactive core of liquid plasma and holographic fractal crystals.

## Features
- Infinite raymarched geode structures with sharp, crystalline inner facets and rocky, dark exteriors.
- Audio-reactive plasma core (`u.config.y`) that pulses and expands.
- Subsurface scattering and internal chromatic refraction in the holographic crystals.
- Mouse gravity well (`u.mouse.xy`) that bends the geode walls and warps the plasma vortex.
- Holographic thin-film interference on the crystal surfaces, creating shifting rainbows.

## Technical Implementation
- File: public/shaders/gen-holographic-plasma-geode.wgsl
- Category: generative
- Tags: ["crystal", "plasma", "audio-reactive", "holographic", "raymarching"]
- Algorithm: Raymarching with domain repetition, Boolean SDF operations (subtraction for geode cavity), and volumetric raycasting for the plasma core.

### Core Algorithm
Uses a repeated box and sphere SDF with noise displacement to create the rocky exterior. A smooth subtraction removes the center to expose the cavity. Inside the cavity, a KIFS fractal generates the holographic crystals, and a volumetric FBM noise creates the swirling plasma core.

### Mouse Interaction
The mouse acts as a gravitational anomaly, warping the space (domain distortion) around the center of the screen, bending the geode structure and accelerating the plasma vortex rotation.

### Color Mapping / Shading
The exterior uses dark, obsidian-like shading with low specular. The crystals use iridescent thin-film interference via a cosine palette mapped to viewing angle and normal. The plasma uses volumetric accumulation with bright neon magenta, cyan, and gold emission.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Holographic Plasma-Geode
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    mouse: vec4<f32>,
    config: vec4<f32>, // x: unused, y: audio/pulse beat, z: unused, w: unused
    zoom_params: vec4<f32>, // custom parameters from sliders
    custom_params: vec4<f32> // additional custom parameters
};

fn hash(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(12.9898, 78.233, 45.164))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let uv = (vec2<f32>(id.xy) * 2.0 - dims) / min(dims.x, dims.y);

    // Raymarching setup
    var ro = vec3<f32>(0.0, 0.0, -3.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    let color = vec3<f32>(0.0);

    textureStore(writeTexture, id.xy, vec4<f32>(color, 1.0));
}
```

Parameters (for UI sliders)

Plasma Intensity (0.5, 0.0, 1.0, 0.01)
Crystal Density (0.5, 0.0, 1.0, 0.01)
Holographic Hue (0.0, 0.0, 1.0, 0.01)
Core Rotation Speed (0.2, 0.0, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
