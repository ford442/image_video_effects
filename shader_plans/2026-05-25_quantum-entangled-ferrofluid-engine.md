# New Shader Plan: Quantum-Entangled Ferrofluid Engine

## Overview
A pulsating, zero-gravity containment field where hyper-magnetic liquid metal aggressively self-organizes into intricate, audio-reactive ferrofluid spikes refracting quantum light.

## Features
- Volumetric ferrofluid rendering using raymarching and smooth min SDFs.
- Dynamic magnetic spiking geometry that erupts in sync with low-frequency audio bands.
- Quantum entanglement visualizer: glowing connections between isolated fluid droplets.
- Chromatic aberration and heavy metallic subsurface scattering on the fluid surface.
- Magnetic field line distortions warping the surrounding spatial grid.

## Technical Implementation
- File: public/shaders/gen-quantum-entangled-ferrofluid-engine.wgsl
- Category: generative
- Tags: ["ferrofluid", "magnetic", "liquid", "quantum", "raymarching", "audio-reactive"]
- Algorithm: Raymarching complex smooth-minimum combinations of spheres and spiked SDFs modulated by 3D noise and audio.

### Core Algorithm
Raymarching scene where the primary object is a central blob. We use a combination of sine waves and 3D Worley noise to perturb the SDF, creating the characteristic "spikes" of ferrofluid in a magnetic field. The amplitude of these spikes is directly driven by `u.zoom_params.w` (audio reactivity) and specific audio bands passed via `u.ripples`.

### Mouse Interaction
Mouse click and drag acts as a powerful localized magnetic pole. The SDF space is warped towards the mouse coordinates (`u.zoom_config.y`, `u.zoom_config.z`), drawing the ferrofluid towards it and elongating the spikes along the vector to the mouse.

### Color Mapping / Shading
A highly metallic PBR-style shading approach. The base color is a deep, iridescent black/purple. We calculate sharp specular highlights based on the surface normal. The surrounding environment (represented analytically) reflects off the fluid, shifting colors based on chromatic aberration and normal displacement.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Quantum-Entangled Ferrofluid Engine
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

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Magnetic Strength, y=Fluid Viscosity, z=Quantum Glow, w=Audio Reactivity
    ripples: array<vec4<f32>, 50>,
};

// ... Raymarching and SDF functions ...
// ... Shading and Lighting ...
// ... Main entry point ...
```
Parameters (for UI sliders)

Name (default, min, max, step)
- Magnetic Strength (1.0, 0.0, 5.0, 0.1)
- Fluid Viscosity (0.5, 0.1, 1.0, 0.05)
- Quantum Glow (1.0, 0.0, 3.0, 0.1)
- Audio Reactivity (1.0, 0.0, 2.0, 0.05)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
