# New Shader Plan: Prismatic Bismuth Lattice

## Overview
An endlessly folding, hyper-geometric expanse of iridescent, stepped bismuth crystals that breathe and fracture in rhythm with unseen cosmic frequencies.

## Features
- Stepped Fractal Geometry: Utilizes recursive SDF combinations to mimic the hopper crystal structure of real bismuth.
- Iridescent Thin-Film Interference: Advanced color mapping that creates iridescent, rainbow-like specular highlights based on viewing angle and surface thickness.
- Audio-Reactive Folding: Deep bass frequencies trigger structural shifts, causing the lattice to fold in on itself or expand.
- Mouse-Driven Fracturing: The cursor emits a localized spatial distortion, subtly twisting the crystal spires and shifting their color palette.
- Volumetric Prismatic Fog: A subtle, multicolored fog that gathers in the deep crevices of the lattice, giving a sense of massive scale.
- Infinite Domain Repetition: Raymarching through an infinite, modulo-wrapped space to create a boundless crystalline labyrinth.

## Technical Implementation
- File: public/shaders/gen-prismatic-bismuth-lattice.wgsl
- Category: generative
- Tags: ["crystalline", "iridescent", "fractal", "geometric", "audio-reactive"]
- Algorithm: Raymarching with domain repetition, recursive box SDFs, and thin-film interference shading.

### Core Algorithm
The scene is built using a raymarching loop. The primary distance field is an infinite grid (`opRep`) of stepped box SDFs (`sdBox`), created by folding and subtracting slightly scaled versions of the same geometry to mimic hopper crystals. A fractional Brownian motion (FBM) displacement is added to the edges to give them a natural, slightly flawed appearance.

### Mouse Interaction
The `u.mouse` coordinates are used to create a spherical warp field. As the camera moves through the space, any crystal within the mouse's radius undergoes a rotational twist (using a 2D rotation matrix on the XZ plane) proportional to the inverse distance from the cursor center.

### Color Mapping / Shading
The surface color is calculated using a thin-film interference approximation. The dot product of the normal and the view direction is used to sample a continuous cosine-based color palette (e.g., `a + b * cos(2 * PI * (c * t + d))`), resulting in vibrant, shifting iridescence. `u.config.y` (audio/beat accumulation) pulses the emissive intensity of the inner geometric cuts.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Prismatic Bismuth Lattice
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// ... (full skeleton with comments)
```

## Parameters (for UI sliders)

Complexity (3.0, 1.0, 6.0, 1.0)
Iridescence (0.5, 0.0, 1.0, 0.01)
Crystal Scale (1.0, 0.5, 5.0, 0.1)
Fog Density (0.2, 0.0, 1.0, 0.01)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
