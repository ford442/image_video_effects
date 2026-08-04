# New Shader Plan: Symbiotic Cyber-Fungal Core-Reactor

## Overview
A biomechanical network of luminescent mycelium feeding off the chaotic energy of a fractured quantum singularity.

## Features
- Intricate volumetric reaction-diffusion simulating cyber-fungal growth
- Dynamic, branching neural pathways pulsing with multi-spectral light
- A central, distorted gravitational anomaly acting as a dark matter core
- Deep subsurface scattering for fleshy, semi-translucent biomechanical tendrils
- Audio-reactive spore emission driven by high-frequency inputs
- Mouse-interactive distortion field that attracts and repels the fungal network

## Technical Implementation
- File: public/shaders/gen-symbiotic-cyber-fungal-core-reactor.wgsl
- Category: generative
- Tags: ["biomechanical", "mycelium", "quantum", "volumetric", "reaction-diffusion"]
- Algorithm: Volumetric raymarching with multi-scale gyroid layers warped by a singularity SDF, utilizing fBM for cellular noise details.

### Core Algorithm
Raymarching scene combining a central sphere (singularity) with a surrounding domain-warped gyroid structure. The gyroid is modified by 3D cellular noise (Voronoi) to create distinct web-like nodes. A localized reaction-diffusion simulation is approximated in the density field using time-stepped fBM sampling.

### Mouse Interaction
The mouse cursor (mapped to `u.zoom_config.yz`) dictates the position of an artificial gravity well. Moving the cursor pulls the fungal tendrils towards it, stretching their SDFs and intensifying their bioluminescent color mapping near the event horizon.

### Color Mapping / Shading
Uses a highly customized subsurface scattering approximation. Outer layers glow with an ethereal cyan-magenta gradient, while deep crevices shift towards deep ultraviolet. The central singularity uses negative color space (inverting light) to simulate a black hole effect with chromatic aberration at its edges.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Symbiotic Cyber-Fungal Core-Reactor
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

Name (default, min, max, step)
- Core Density (1.0, 0.1, 5.0, 0.1)
- Mycelium Spread (0.5, 0.0, 1.0, 0.05)
- Quantum Noise (0.3, 0.0, 1.0, 0.01)
- Temporal Shift (1.0, 0.0, 2.0, 0.1)
- Mutation Rate (0.1, 0.0, 0.5, 0.01)
