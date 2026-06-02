# New Shader Plan: Ethereal-Aurora Ghost-Orchid

## Overview
A phantom-like, hyper-dimensional orchid whose transparent, glowing petals are formed entirely from captured aurora borealis, blooming and disintegrating infinitely in a volumetric dark-matter void, driven by acoustic resonance.

## Features
- **Hyper-Dimensional Petal Geometry**: Infinite, non-Euclidean orchid petals modeled using complex smooth-min SDF combinations and domain-warped noise.
- **Volumetric Auroral Subsurface-Scattering**: Deep, multi-layered color mapping simulating ethereal, glowing aurora gas trapped within transparent organic bounds.
- **Audio-Reactive Blooming Mechanism**: The entire orchid structure breathes, dilates, and violently unfurls its geometric stamen based on dynamic acoustic impulses.
- **Quantum-Dust Pollen Swarm**: Thousands of luminous particulate pollen specks constantly orbit the core in a swirling, particle-driven vortex.
- **Dark-Matter Void Lighting**: High-contrast, cinematic lighting using raymarched soft shadows and glowing bloom to isolate the subject in an infinite abyssal space.
- **Interactive Gravitational Stem**: The core stamen dynamically bends and tracks the mouse cursor, pulling the entire blossom towards the observer via an organic gravity-well function.

## Technical Implementation
- File: public/shaders/gen-ethereal-aurora-ghost-orchid.wgsl
- Category: generative
- Tags: ["organic", "aurora", "floral", "audio-reactive", "raymarching"]
- Algorithm: Raymarching volumetric SDFs with multi-octave FBM for auroral displacement, coupled with a secondary particle-like pollen system integrated into the raymarch step.

### Core Algorithm
The base geometry uses a polar-repeated, smoothly blended capsule and thin-plate SDFs wrapped along a central spline to form the petals and stem. A time-varying 3D Fractional Brownian Motion (FBM) field displaces the surface, creating the illusion of flowing, gaseous tissue. The internal density is calculated by sampling the SDF thickness, accumulating an emission integral along the ray for the aurora effect.

### Mouse Interaction
The mouse cursor projects a 3D coordinate that acts as a localized gravitational attractor. A soft `length(p - mouse_pos)` falloff is applied to the SDF coordinates of the stamen and inner petals, warping them smoothly towards the cursor while maintaining organic tension.

### Color Mapping / Shading
A highly spectral gradient combining cyan, deep violet, and ethereal green. Instead of standard diffuse lighting, shading relies almost entirely on raymarched emission and exponential density accumulation. A post-processing bloom pass amplifies the auroral glow, contrasting sharply with a pure black, dark-matter background.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Ethereal-Aurora Ghost-Orchid
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

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```

Parameters (for UI sliders)

Petal Complexity (3.0, 1.0, 10.0, 0.1)
Aurora Intensity (2.0, 0.5, 5.0, 0.1)
Audio Reactivity (1.5, 0.0, 3.0, 0.1)
Pollen Density (5.0, 0.0, 10.0, 0.5)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
