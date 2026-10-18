# New Shader Plan: Ethereal Chrono-Fluid Symbiote

## Overview
A flowing, temporal liquid entity that responds dynamically to audio and mouse interactions, weaving through dimensions of time and space in a continuous symbiotic dance.

## Features
- Audio-reactive temporal distortion
- Non-Euclidean fluid dynamics
- Ethereal subsurface scattering
- Interactive symbiotic gravity wells
- Bioluminescent crystalline structures
- Fractal chrono-vortices

## Technical Implementation
- File: public/shaders/gen-ethereal-chrono-fluid-symbiote.wgsl
- Category: generative
- Tags: ["fluid", "temporal", "symbiote", "ethereal", "audio-reactive"]
- Algorithm: Raymarching with domain warping, 4D noise, and fluid simulation approximations based on distance functions.

### Core Algorithm
The algorithm uses a raymarching approach. Domain repetition and 4D noise are combined to create non-Euclidean fluid structures. The SDF (Signed Distance Field) will incorporate fractional Brownian motion (fBm) to give a liquid, flowing texture that evolves over time (chrono). Audio data (bass and high frequencies) will modulate the density and the warp intensity of the domain.

### Mouse Interaction
The mouse will create a symbiotic gravity well. When the user interacts (`u.zoom_config.w > 0.0`), the fluid will be drawn towards the mouse's UV coordinates, warping the surrounding space and bending the light rays. The distortion formula will use an inverse square law modified by sine waves to create a pulsating attraction effect.

### Color Mapping / Shading
The shading will use an ethereal color palette (teals, purples, bioluminescent greens). Subsurface scattering approximations will be used to give the fluid a translucent, gummy appearance. A metallic sheen will be applied to the crystalline structures embedded within the fluid. Bloom will be prominent around the high-intensity energy nodes.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Ethereal Chrono-Fluid Symbiote
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, yz=MouseUV, w=MouseDown
    zoom_params: vec4<f32>,  // x=Density, y=Spore Glow, z=Twist, w=Fog
    ripples: array<vec4<f32>, 50>,
};

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

const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;

// ... (full skeleton with comments)
// Helper functions for noise and rotation
// Raymarching loop
// Lighting and shading calculations
// Main compute function
```

## Parameters (for UI sliders)

Name (default, min, max, step)
- Density (1.0, 0.1, 5.0, 0.1) -> Maps to zoom_params.x
- Fluid Viscosity (0.5, 0.0, 1.0, 0.01) -> Maps to zoom_params.y
- Chrono Warp (1.0, 0.0, 5.0, 0.1) -> Maps to zoom_params.z
- Symbiote Glow (1.0, 0.0, 3.0, 0.1) -> Maps to zoom_params.w

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
