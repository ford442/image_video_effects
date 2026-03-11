# New Shader Plan: Quantum Mycelium

## Overview
A hyper-organic, microscopic journey through an infinitely growing, glowing fungal network that pulses with data-like energy and branches dynamically based on spatial noise.

## Features
- **Infinite Fractal Branching**: Utilizes raymarching with specialized domain warping to simulate organic, chaotic hyphal growth patterns.
- **Bioluminescent Energy Pulses**: Bright, data-like energy packets travel along the mycelial threads, driven by audio frequencies (`u.config.y`).
- **Volumetric Spore Clouds**: A dense, atmospheric scattering effect simulating microscopic spores floating in the deep void.
- **Magnetic Mouse Repulsion**: The cursor acts as a toxic or magnetic field, causing the delicate threads to bend, wither, or aggressively route around the interaction point.
- **Subsurface Fungal Shading**: The strands exhibit a fleshy, translucent quality using a cheap subsurface scattering approximation based on inverted normals.

## Technical Implementation
- File: public/shaders/gen-quantum-mycelium.wgsl
- Category: generative
- Tags: ["organic", "microscopic", "fungal", "network", "audio-reactive"]
- Algorithm: Raymarching with 3D noise-displaced cylinders, recursive branching via spatial folding, and volumetric density accumulation.

### Core Algorithm
The scene uses raymarching through a space warped by 3D Fractional Brownian Motion (FBM) and domain repetition (`opRep`). The primary structural SDF is a continuous cylinder (`sdCylinder`) that gets twisted and displaced by the noise field to look like organic root systems. Spatial folding (`abs(p)`) is used at specific intervals to create the illusion of complex, fractal-like branching without the heavy cost of actual recursion.

### Mouse Interaction
The `u.mouse` coordinates map to a 3D repulsion sphere. When the raymarching position nears the mouse's projected 3D space, an inverse-distance distortion function strongly repels the vertex positions of the mycelial threads, stretching and thinning the cylinders (using a smooth minimum `smin` blending with a large void sphere) to simulate the network routing around the cursor.

### Color Mapping / Shading
The base material uses a subsurface scattering trick: sampling the SDF slightly deeper into the surface (`p - normal * 0.15`) and adding that inverted distance to the emissive term for a fleshy, translucent look. Bright, neon energy pulses travel along the lengths of the cylinders using a sine wave function based on the fragment's world position and `u.config.y` (the audio accumulator).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Quantum Mycelium
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// SDF Primitives
// smin (Polynomial smooth minimum)
// sdCylinder
// opRep (Domain Repetition)

// Helpers
// rot2D (2D Rotation Matrix)
// hash33 (3D Noise)
// fbm (Fractional Brownian Motion)

// Map Function
// - Applies infinite domain repetition for the environment.
// - Distorts spatial coordinates (p) using 3D FBM to twist the cylinders into organic shapes.
// - Uses spatial folding to simulate branching.
// - Repels geometry near u.mouse.
// - Returns vec2(distance, material_id).

// Lighting & Shading
// - Computes normals.
// - Calculates fake subsurface scattering for fleshy fungal texture.
// - Injects bioluminescent energy pulses moving along the threads scaled by u.config.y (audio pulse).

// Compute Shader Entry Point
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // 1. Ray setup and camera matrix
    // 2. Raymarching loop (break on max distance or hit)
    // 3. Shading and color accumulation
    // 4. Volumetric spore cloud application
    // 5. writeTexture update
}
```

## Parameters (for UI sliders)

Network Density (1.5, 0.5, 3.0, 0.1)
Growth Chaos (0.8, 0.0, 2.0, 0.05)
Pulse Speed (2.0, 0.1, 5.0, 0.1)
Spore Thickness (0.5, 0.0, 1.0, 0.05)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
