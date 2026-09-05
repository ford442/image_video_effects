# New Shader Plan: Fractal Neuro-Mycelium Lattice

## Overview
A hyper-connected, pulsating network of organic filaments that endlessly branches and bridges across void space, resembling the synaptic flashes of a cosmic brain. The aesthetic fuses bioluminescent fungal growth with cyberpunk neural pathways, rendering ethereal threads of light that intelligently route around gravity wells.

## Features
- Dynamic, branching volumetric filament generation using a custom 3D organic cellular noise algorithm.
- Audio-reactive synaptic flashes traversing the network pathways based on FFT bass and mid frequencies.
- Real-time raymarching through a continuously expanding fractal domain structure.
- Mouse-driven gravity anchors that bend and reroute growing mycelium threads dynamically.
- Chromatic dispersion shading creating iridescent, glowing edges along microscopic filament bridges.
- Subsurface scattering approximations for a translucent, gelatinous organic feel.

## Technical Implementation
- File: public/shaders/gen-fractal-neuro-mycelium-lattice.wgsl
- Category: generative
- Tags: ["organic", "neural", "mycelium", "fractal", "bioluminescent", "audio-reactive"]
- Algorithm: Raymarching combined with domain repetition and volumetric density accumulation based on Voronoi-noise graphs, deformed by mouse position and audio data.

### Core Algorithm
The core utilizes a smooth-min combined Voronoi and Simplex noise function evaluated within a raymarching loop. By using domain repetition, the structure appears infinite. Filaments are defined as cylindrical Signed Distance Fields (SDFs) connecting adjacent Voronoi cell centers. Density accumulation calculates the thickness of the mycelium, allowing for volumetric rendering rather than hard surfaces. Audio data modulates the density and emission strength, creating propagating flashes along the network.

### Mouse Interaction
The mouse acts as a gravitational singularity or "nutrient source". The SDF of the filaments is warped toward the mouse position in 3D space (`zoom_config.yz` mapped to world coordinates). Moving the mouse slowly causes the network to stretch and bridge toward it; fast movements tear the delicate filaments, resulting in explosive particle-like dissipation that slowly regrows.

### Color Mapping / Shading
Filaments possess a base translucent milky-white color mixed with deep subsurface blues and purples. When active (via audio or proximity to mouse), they erupt in bioluminescent cyan and gold. The shading model incorporates a fake subsurface scattering pass by sampling the SDF slightly deeper along the ray direction, mixed with high-intensity additive blending for the glowing nodes and a subtle chromatic aberration near the screen edges.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Fractal Neuro-Mycelium Lattice
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
  zoom_params: vec4<f32>,  // .x = Branch Density, .y = Flow Speed, .z = Glow Intensity, .w = Audio Reactivity
  ripples: array<vec4<f32>, 50>,
};

// --- CORE UTILITIES ---
const MAX_STEPS = 100;
const MAX_DIST = 50.0;
const SURF_DIST = 0.01;

// ... Utility functions for noise, smooth min, rotation matrices ...

// --- SDF & NOISE ---
fn map(p: vec3<f32>) -> f32 {
    // 1. Calculate base voronoi/cellular noise for node positions
    // 2. Warp space based on mouse position
    // 3. Connect nodes with cylindrical SDFs using smooth-min
    // return distance
    return 0.0;
}

// --- RAYMARCHING & SHADING ---
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> f32 {
    // standard raymarching loop
    return 0.0;
}

// --- MAIN COMPUTE ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // 1. Handle screen coordinates and aspect ratio
    // 2. Set up camera, incorporate mouse interaction
    // 3. Perform raymarching & volumetric accumulation
    // 4. Sample dataTextureC for audio data to modulate glow
    // 5. Output to writeTexture
}
```

Parameters (for UI sliders)

Branch Density (default: 1.0, min: 0.1, max: 5.0, step: 0.1)
Flow Speed (default: 0.5, min: 0.0, max: 2.0, step: 0.05)
Glow Intensity (default: 1.5, min: 0.0, max: 5.0, step: 0.1)
Audio Reactivity (default: 1.0, min: 0.0, max: 3.0, step: 0.1)
