# New Shader Plan: Xeno-Botanical Synth-Flora

## Overview
A dense, alien jungle of luminescent, synthetic flora that blooms and breathes with the rhythm of sound, blending organic curves with crystalline cybernetic materials.

## Features
- **Extraterrestrial Foliage:** Raymarched organic structures using domain-repeated, twisted capped cones and FBM displacement to simulate sprawling vines.
- **Bioluminescent Blooming:** Giant fractal flowers that pulse, expand, and shift through iridescent color gradients driven by audio (`u.config.y`).
- **Subsurface Cyber-Scattering:** Translucent organic surfaces that scatter light, revealing sharp, glowing mechanical circuitry underneath.
- **Volumetric Spore Swarm:** A floating, glowing dust of drifting pollen that interacts with light and cast shadows.
- **Interactive Repulsion:** Flora dynamically bends and shies away from the cursor's position, parting like tall grass.
- **Liquid-Metal Dewdrops:** Highly reflective spheres clinging to vines that reflect the neon environment.

## Technical Implementation
- File: public/shaders/gen-xeno-botanical-synth-flora.wgsl
- Category: generative
- Tags: ["organic", "botanical", "cybernetic", "bioluminescent", "audio-reactive"]
- Algorithm: Raymarching with domain repetition, non-linear domain warping for plant growth, and multi-layered material shading (subsurface scattering + metallic).

### Core Algorithm
Uses domain repetition (`opRep`) to create a dense forest. The SDFs rely on `sdCappedCone` and `sdCylinder` with twist operations and sine-wave domain warping to simulate organic growth. A complex FBM noise function displaces the surface to create ribbed, leaf-like textures.

### Mouse Interaction
Calculates the distance from the raymarched point to the 3D projection of the mouse (`u.mouse`). Applies a repelling displacement vector to the domain before evaluating the plant SDF, causing the vines to bend away smoothly.

### Color Mapping / Shading
Shading combines a fast subsurface scattering approximation (sampling SDF thickness behind the normal) with a metallic specular layer for the internal cybernetic parts. The bioluminescence uses sine-based color palettes that cycle based on time and audio input.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Xeno-Botanical Synth-Flora
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// SDF Primitives
// sdCylinder, sdCappedCone
// opRep (Domain Repetition)
// opTwist, opBend (Domain Warping)

// Helpers
// rot2D (2D Rotation Matrix)
// fbm (Fractal Brownian Motion for textures)
// palette (Cosine based color palettes)

// Map Function
// - Warps space based on u.mouse for interaction.
// - Defines the organic vines and fractal blooms.
// - Displaces surfaces with FBM.
// - Returns vec2(distance, material_id).

// Shading & Lighting
// - Computes normals.
// - Approximates subsurface scattering by marching slightly inside the SDF.
// - Modulates bloom and emission with u.config.y.

// Compute Shader Entry Point
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // 1. Setup ray origin and direction based on uv and time
    // 2. Raymarching loop with dynamic step sizes for complex FBM
    // 3. Shading: calculate lighting, SSS, and bioluminescence
    // 4. Volumetric integration for floating spores
    // 5. writeTexture update
}
```

## Parameters (for UI sliders)

- Flora Density (2.0, 0.5, 5.0, 0.1)
- Bloom Intensity (1.5, 0.0, 3.0, 0.1)
- Cyber-Circuit Glow (0.8, 0.0, 2.0, 0.1)
- Growth Warp (1.0, 0.1, 3.0, 0.1)

## Integration Steps

- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
