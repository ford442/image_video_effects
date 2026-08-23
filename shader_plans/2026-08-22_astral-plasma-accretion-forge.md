# New Shader Plan: Astral Plasma Accretion Forge

## Overview
A hyper-dense, cosmic forge where swirling ribbons of superheated plasma are drawn into a blinding gravitational singularity, forging heavy elements in a radiant celestial crucible.

## Features
- **Singularity Core:** A central gravitational lens that distorts the surrounding plasma streams and spacetime.
- **Accretion Disk Dynamics:** Swirling, chaotic fluid-like noise mapping that simulates superheated plasma flowing into the core.
- **Thermodynamic Color Mapping:** Intense temperature gradients shifting from deep ultraviolet to blinding white-hot corona.
- **Magnetic Flux Lines:** Arcing, glowing filaments snapping and reconnecting around the singularity.
- **Audio-Reactive Flare Eruptions:** Pulsing energy waves that burst outward along the polar axes in sync with low-frequency audio.
- **Volumetric Bloom Simulation:** Multi-layered additive blending to simulate blinding light scattering through cosmic dust.
- **Mouse-Driven Gravitational Anomaly:** The mouse acts as a wandering micro-black hole, pulling and twisting the accretion disk.

## Technical Implementation
- File: public/shaders/gen-astral-plasma-accretion-forge.wgsl
- Category: generative
- Tags: ["cosmic", "plasma", "singularity", "accretion", "volumetric"]
- Algorithm: Raymarching combined with domain warping, chaotic 3D noise (FBM), and gravitational lensing distortion based on distance to the center.

### Core Algorithm
Raymarching through a volumetric density field shaped by multiple octaves of 3D Simplex noise and fractional Brownian motion (FBM). The coordinate space (UVs/Ray origins) is non-linearly distorted (folded and twisted) to simulate gravitational lensing near the origin. The accretion disk is represented as a dense, flattened torus of noise that rotates over time, with radial inflow applied to the noise coordinates.

### Mouse Interaction
The mouse coordinates map to a localized coordinate distortion in the 2D plane (or 3D ray origins), applying a swirl effect and intensifying the plasma brightness (temperature) where the mouse pulls the fluid.

### Color Mapping / Shading
A high-dynamic-range (HDR) palette based on blackbody radiation curves. Colors are calculated using smoothstep and pow functions mapped to the accumulated density of the raymarch. Base colors are dark purples and blues, scaling up to intense oranges, yellows, and white at high density/proximity to the core. A fake volumetric bloom is applied by accumulating color even outside the dense geometry regions based on an inverse-square distance falloff from the core.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Astral Plasma Accretion Forge
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Core Density, .y = Accretion Spin, .z = Flux Intensity, .w = Core Temp
  ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```

Parameters (for UI sliders)

Core Density (0.5, 0.1, 1.0, 0.01)
Accretion Spin (0.3, 0.0, 1.0, 0.01)
Flux Intensity (0.5, 0.0, 1.0, 0.01)
Core Temp (0.7, 0.0, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
