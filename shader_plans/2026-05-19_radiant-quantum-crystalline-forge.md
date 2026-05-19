# New Shader Plan: Radiant Quantum-Crystalline Forge

## Overview
A majestic, zero-gravity forge where infinite quantum crystals self-assemble into intricate fractal geometries, pulsating with radiant chromatic energy and refracting light in a dazzling abyssal void.

## Features
- Infinite KIFS (Kaleidoscopic Iterated Function System) crystalline fractals
- Chromatic dispersion and internal refraction rendering
- Audio-reactive crystallization speed and shattering effects
- Volumetric quantum fog surrounding the structures
- Gravity-well distortion fields interacting with mouse inputs

## Technical Implementation
- File: public/shaders/gen-radiant-quantum-crystalline-forge.wgsl
- Category: generative
- Tags: ["fractal", "crystal", "quantum", "reactive", "volumetric"]
- Algorithm: Raymarching through a Kaleidoscopic Iterated Function System (KIFS) with chromatic dispersion, volumetric fog accumulation, and audio-reactive domain warping.

### Core Algorithm
Raymarching a KIFS fractal SDF. The geometry is folded using multi-axis rotation and absolute value mirroring. The distance field is modified by audio spectral data to drive the expansion and contraction of the crystal facets. Subsurface scattering and chromatic dispersion are simulated by offsetting rays per color channel.

### Mouse Interaction
The mouse acts as a supermassive gravity well, warping the ray direction spherically around its coordinates, causing the crystal lattice to bend and distort like a gravitational lens.

### Color Mapping / Shading
Iridescent thin-film interference gradients applied based on viewing angle (Fresnel) and SDF normal. Deep shadows are filled with a luminous quantum fog (volumetric glow) that shifts in hue based on the audio low-frequency envelope.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Radiant Quantum-Crystalline Forge
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// --- INTERNAL CONSTANTS & STRUCTS ---
// KIFS Iterations and Color Constants
// ...

// --- MAIN COMPUTE SHADER ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // 1. Calculate UVs and normalized coordinates
    // 2. Apply mouse gravity well distortion
    // 3. Raymarch KIFS SDF
    // 4. Calculate surface normals and chromatic dispersion
    // 5. Accumulate volumetric fog
    // 6. Write to output texture
}
```

Parameters (for UI sliders)

Crystallization Density (0.5, 0.0, 1.0, 0.01)
Chromatic Aberration (1.0, 0.0, 5.0, 0.1)
Fog Intensity (0.8, 0.0, 2.0, 0.05)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
