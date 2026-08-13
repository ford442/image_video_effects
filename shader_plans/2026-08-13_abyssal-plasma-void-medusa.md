# New Shader Plan: Abyssal Plasma Void-Medusa

## Overview
A majestic, deep-space biomechanical entity undulating through a quantum fluidic void, driven by audio-reactive bioluminescent plasma nodes.

## Features
- Fluidic domain distortion to simulate liquid space.
- Audio-reactive pulsing across translucent bio-membranes.
- Volumetric subsurface scattering for the jelly-bell.
- Smooth min (smin) organic tentacles that react to gravitational drag.
- Quantum noise-driven plasma trails.

## Technical Implementation
- File: public/shaders/gen-abyssal-plasma-void-medusa.wgsl
- Category: generative
- Tags: ["organic", "fluid", "bioluminescent", "plasma", "audio-reactive"]
- Algorithm: Raymarching through domain-distorted SDFs with volumetric light integration and audio-driven displacement.

### Core Algorithm
Raymarching an inverted-hemisphere shell (the bell) combined with trailing sine-modulated capsule SDFs (the tentacles). The entire space is distorted by low-frequency 3D noise and time to create a fluid, underwater feeling.

### Mouse Interaction
The mouse (`u.zoom_config.yz`) applies a rotational gravitational warp, dragging the medusa's tentacles toward the cursor's orbit and bending the local space.

### Color Mapping / Shading
A deep oceanic background transitioning to void-black, lit by internal emission nodes mapped to frequency data from `dataTextureC`. Volumetric integration during the raymarch step adds a soft glowing bloom to the edges of the biological structures.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Abyssal Plasma Void-Medusa
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
  zoom_params: vec4<f32>,  // .x = parameter1, .y = parameter2, .z = parameter3, .w = parameter4
  ripples: array<vec4<f32>, 50>,
};
// ... (full skeleton with comments)
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Bioluminescence (0.5, 0.0, 1.0, 0.01) -> zoom_params.x
- Fluid Distortion (0.3, 0.0, 1.0, 0.01) -> zoom_params.y
- Tentacle Length (0.8, 0.2, 1.5, 0.01) -> zoom_params.z
- Plasma Hue (0.5, 0.0, 1.0, 0.01) -> zoom_params.w

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
