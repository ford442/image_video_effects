# New Shader Plan: Gravitational Ferrofluid Singularity-Engine

## Overview
A hyper-dense, magnetic-liquid simulation that bends light and space around a central, interactive black-hole gravity well, merging dark metallic sheens with vibrant cosmic radiation.

## Features
- Interactive black hole: Mouse acts as a gravity well, pulling and twisting the ferrofluid.
- Magnetic spikes: Raymarched domain featuring spiky, metallic formations that respond to "magnetic" fields (noise and time).
- Event horizon lensing: Extreme spatial distortion near the singularity, bending the background nebula.
- Iridescent metallic shading: Physically-inspired lighting with sharp specular highlights and chromatic aberration.
- Quantum foam background: A dynamic, high-frequency noise base simulating the vacuum of space.
- Audio-reactive pulses: Parameters tied to time variations to create a heartbeat-like resonance.

## Technical Implementation
- File: public/shaders/gen-gravitational-ferrofluid-singularity-engine.wgsl
- Category: generative
- Tags: ["ferrofluid", "singularity", "raymarching", "interactive", "metallic", "iridescent"]
- Algorithm: Raymarching an SDF of a liquid metallic structure with intense domain distortion driven by a singularity.

### Core Algorithm
Raymarching a combination of spherical and noise-displaced SDFs. The ferrofluid spikes are generated using a 3D noise function mapped onto a base sphere. The domain itself is warped using a logarithmic spiral function to simulate the gravitational pull of the singularity.

### Mouse Interaction
The mouse coordinates (`let mouse = u.zoom_config.yz;`) define the 2D screen-space position of the singularity. This position is projected into 3D space. The distance from the ray to the singularity inversely scales the domain, creating a pinch/lens effect.

### Color Mapping / Shading
Uses a complex BRDF-like shading model. Base color is a dark, sleek obsidian. As distance to the singularity decreases, an intense, iridescent glowing rim light (mapped via normal angles and view vectors) takes over, creating the "cosmic radiation" look.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Gravitational Ferrofluid Singularity-Engine
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
  zoom_params: vec4<f32>,  // .x = Singularity Mass, .y = Fluid Viscosity, .z = Spike Density, .w = Iridescence
  ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```

## Parameters (for UI sliders)
- Singularity Mass (0.5, 0.0, 1.0, 0.01) - Controls the radius and pull of the central black hole. mapped to `zoom_params.x`
- Fluid Viscosity (0.3, 0.1, 1.0, 0.01) - Alters the speed and smoothness of the noise function driving the ferrofluid spikes. mapped to `zoom_params.y`
- Spike Density (0.7, 0.1, 2.0, 0.05) - Modulates the frequency of the 3D noise on the SDF. mapped to `zoom_params.z`
- Iridescence (0.6, 0.0, 1.0, 0.01) - Shifts the color palette of the metallic reflections and rim lighting. mapped to `zoom_params.w`