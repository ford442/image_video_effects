# New Shader Plan: Luminescent Chrono-Fluid Astrolabe

## Overview
A hyper-intricate, multi-dimensional astrolabe forged from flowing liquid-gold plasma and hard-light holograms, endlessly spinning and realigning its cosmic rings in perfect synchronization with audio frequencies.

## Features
- **Fluidic Orbital Rings**: Concentric rings made of liquid metal that flow and ripple while maintaining strict geometric orbits.
- **Holographic Core**: A glowing, translucent cosmic map at the center that projects volumetric light rays into the surrounding space.
- **Audio-Reactive Realignment**: Heavy bass frequencies cause the astrolabe's rings to abruptly shift on their axes, mimicking a cosmic clock ticking.
- **Nebula Dust Interference**: The surrounding void is filled with stardust that gets swept into vortexes by the gravitational pull of the rings.
- **Chromatic Dispersion**: Light bending through the holographic core creates a beautiful, prismatic lens flare effect along the edges.

## Technical Implementation
- File: public/shaders/gen-luminescent-chrono-fluid-astrolabe.wgsl
- Category: generative
- Tags: ["cosmic", "mechanical", "liquid", "holographic", "audio-reactive"]
- Algorithm: Raymarching combined with domain repetition, fluid noise displacement along torus SDFs, and volumetric ray accumulation.

### Core Algorithm
- **SDF Composition**: Multiple nested `sdTorus` functions representing the rings, heavily rotated along different time-based axes.
- **Fluid Displacement**: A 3D simplex noise function offsets the surface of the tori, giving them a liquid, flowing appearance.
- **Volumetric Rendering**: Raymarching accumulates glowing density near the center (`sdSphere`) and inside the holographic projection cones.

### Mouse Interaction
- **Gravity Well / Orbit**: The mouse acts as a gravitational attractor. Moving it shifts the global rotation axis of the astrolabe and pulls the nebula dust towards the cursor using an inverse-square distance formula.

### Color Mapping / Shading
- **Iridescent Liquid Metal**: The rings use a highly reflective metallic BRDF with a base color sampled from a warm gold/cyan gradient.
- **Core Bloom**: The center projects bright, additive cyan-magenta light, creating an intense bloom effect over the structure.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Luminescent Chrono-Fluid Astrolabe
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// --- UTILITY FUNCTIONS ---
// ... (rotate, noise3D, sdTorus, etc.)

// --- SDF SCENE ---
// ... (nested tori with noise displacement)

// --- RAYMARCHING ---
// ... (volumetric accumulation and surface lighting)

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // ... (camera setup, raymarching loop, color mixing, texture write)
}
```

## Parameters (for UI sliders)
- Ring Complexity (3.0, 1.0, 10.0, 1.0)
- Fluidity (0.5, 0.0, 1.0, 0.01)
- Core Glow Intensity (1.5, 0.1, 5.0, 0.1)
- Rotation Speed (1.0, 0.0, 5.0, 0.1)

## Integration Steps
- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
