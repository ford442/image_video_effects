# New Shader Plan: Neon-Plasma Biomechanical Hive

## Overview
A hyper-organic, biomechanical labyrinth of pulsing neon circuitry and breathing metallic tissue that spawns luminescent plasma-spores reacting to ambient cosmic frequencies.

## Features
- **Breathing Metallic Tissue:** A base layer of Voronoi-driven organic metallic structures that physically expands and contracts like living lungs.
- **Neon Circuit-Veins:** Infinite, branching fractal lightning that flows through the metallic tissue, pulsing with intense neon data streams.
- **Plasma-Spore Eruption:** Audio-reactive generation of glowing, floating energy spores that burst from the hive's pores during heavy bass hits.
- **Magnetic Mouse Singularity:** The user's cursor acts as a localized gravity well, violently pulling veins and spores toward it while warping the surrounding metal.
- **Holographic Chromatic Aberration:** Edge-based color splitting and holographic interference patterns that give the hive an unstable, multi-dimensional appearance.

## Technical Implementation
- File: public/shaders/gen-neon-plasma-biomechanical-hive.wgsl
- Category: generative
- Tags: ["biomechanical", "neon", "organic", "plasma", "audio-reactive", "cyberpunk"]
- Algorithm: Raymarching combined with domain repetition, fractal Brownian motion (fBm), and 3D Voronoi cellular displacement.

### Core Algorithm
- **Raymarching / SDFs:** Raymarch a domain-repeated grid of organic structures (SDF spheres blended with cylinders via smin).
- **Voronoi Displacement:** Displace the SDF surfaces using 3D Voronoi noise to create the porous, metallic tissue texture.
- **fBm Veins:** Layer high-frequency, glowing fBm noise across the surface to simulate the branching neon circuitry.
- **Spore Particles:** Simulate floating plasma-spores using secondary raymarched spheres with a time-varying, audio-linked emission intensity.

### Mouse Interaction
- **Magnetic Singularity:** Calculate distance from ray position to mouse coordinates projected into 3D space. Apply an inverse-square attraction force that bends the ray paths (`p -= normalize(mousePos - p) * strength / dist`).
- **Surface Ripples:** Clicking generates expanding shockwaves (using `u.zoom_config.w` and ripples array) that propagate across the metallic tissue, momentarily disrupting the neon veins.

### Color Mapping / Shading
- **Material Properties:** High specular reflection for the metallic tissue, using a dark gunmetal base color.
- **Emission:** Intense, HDR-level emission for the neon veins and plasma-spores, utilizing `plasmaBuffer` to shift from cyan to magenta based on audio input.
- **Chromatic Aberration:** Sample the final scene multiple times with slight spatial offsets for R, G, and B channels to create the holographic interference effect.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Neon-Plasma Biomechanical Hive
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// --- PARAMETERS ---
// These will be bound via UI sliders
// Parameter 1: Hive Breathing Speed
// Parameter 2: Neon Intensity
// Parameter 3: Spore Density
// Parameter 4: Magnetic Pull Strength

// --- HELPER FUNCTIONS ---
// smin, rot, hash, noise3D, voronoi3D, fBm

// --- SDF DEFINITIONS ---
// map(p): Returns distance to the biomechanical hive surface and material ID.

// --- MAIN RAYMARCHER ---
// raymarch(ro, rd): Calculates intersection and accumulates volumetric spore glow.

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // 1. Setup coordinates and camera (including mouse interaction)
    // 2. Perform raymarching
    // 3. Calculate lighting, material properties, and neon emission
    // 4. Apply chromatic aberration and final tone mapping
    // 5. Write to writeTexture
}
```

## Parameters (for UI sliders)

Name (default, min, max, step)
- Hive Breathing Speed (1.0, 0.1, 5.0, 0.1)
- Neon Intensity (2.0, 0.0, 10.0, 0.1)
- Spore Density (0.5, 0.0, 1.0, 0.05)
- Magnetic Pull (1.5, 0.0, 5.0, 0.1)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
