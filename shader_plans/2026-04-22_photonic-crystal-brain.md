# New Shader Plan: Photonic Crystal-Brain

## Overview
An infinite, glowing network of hyper-refractive crystal neurons that fire iridescent plasma pulses in sync with audio frequencies, generating volumetric glowing synapses within a dark cosmic void.

## Features
- **Hyper-Refractive Raymarching:** Complex dielectric materials simulating light bending through infinite crystalline neural pathways.
- **Audio-Reactive Synapses:** Bright bursts of plasma (driven by audio amplitude) that shoot along the synaptic connections.
- **Infinite Domain Repetition:** The brain structure expands endlessly in all directions using 3D spatial folding.
- **Volumetric Glowing Plasma:** Glowing trails left by the signals, illuminating the dark void.
- **Mouse-Driven Focus:** Mouse coordinates attract the neural firing pathways and distort the crystalline lattice like a gravitational lens.

## Technical Implementation
- File: public/shaders/gen-photonic-crystal-brain.wgsl
- Category: generative
- Tags: ["neural", "crystal", "plasma", "organic", "audio-reactive", "raymarching"]
- Algorithm: Raymarching combined with domain repetition, smooth-min (smin) for organic neural connections, and volumetric accumulation for plasma glows.

### Core Algorithm
- Use an SDF (Signed Distance Field) for a web-like structure built from intersecting cylinders with smooth-min blending to create organic, webbed neural junctions.
- Apply domain repetition (`p = mod(p, spacing) - spacing/2`) to create an endless grid of these junctions.
- Displace the surface using 3D fractional Brownian motion (FBM) noise to give the neurons a jagged, crystalline texture.
- Compute surface normals and simulate refraction using a high index of refraction to give the neurons a glass-like appearance.

### Mouse Interaction
- The mouse position acts as a powerful 'thought center', locally bending the SDF domain towards the cursor in 3D space, drawing the neural branches closer together.
- This creates a gravity-well effect where the crystal matrix becomes denser and brighter around the interaction point.

### Color Mapping / Shading
- The base material is dark, hyper-refractive crystal, heavily relying on environment mapping or simulated background light.
- Pulses are rendered using volumetric accumulation along the ray, colored with iridescent, shifting gradients (cyan to magenta) based on `u.config.x` (time) and `u.config.y` (audio).
- High-intensity specular highlights make the crystal edges pop against the dark void.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Photonic Crystal-Brain
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Synapse Density, y=Pulse Speed, z=Crystal Distortion, w=Glow Intensity
    ripples: array<vec4<f32>, 50>,
};

// ... (Rest of raymarching functions, SDFs, FBM, and main logic) ...
```

## Parameters (for UI sliders)

Name (default, min, max, step)
- Synapse Density (1.0, 0.5, 3.0, 0.1)
- Pulse Speed (1.0, 0.1, 5.0, 0.1)
- Crystal Distortion (0.5, 0.0, 2.0, 0.05)
- Glow Intensity (1.5, 0.0, 5.0, 0.1)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-04-22_photonic-crystal-brain.md" "Photonic Crystal-Brain"
