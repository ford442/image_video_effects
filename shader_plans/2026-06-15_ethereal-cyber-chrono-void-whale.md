# New Shader Plan: Ethereal Cyber-Chrono Void-Whale

## Overview
A colossal, slow-moving biomechanical space leviathan swimming gracefully through a dense volumetric plasma-ocean, whose transparent cyber-skeletal ribs refract and ripple with shifting temporal energy streams.

## Features
- Majestic, slow-swimming leviathan modeled using tubular SDFs
- Volumetric, deeply glowing cyber-skeletal ribs that reveal an internal glowing core
- Dense, aether-plasma ocean that reacts subtly to its movements
- Temporal energy streams cascading around the creature that glitch in time
- Acoustic reactivity causing the core to bloom intensely on low frequency drops

## Technical Implementation
- File: public/shaders/gen-ethereal-cyber-chrono-void-whale.wgsl
- Category: generative
- Tags: ["organic", "cosmic", "mechanical", "void", "volumetric"]
- Algorithm: Raymarching against a complex SDF defining the leviathan structure, layered with dense volumetric fog calculations to simulate the plasma ocean and temporal streams.

### Core Algorithm
Raymarch through an unbounded volume where the leviathan is defined using a blend of `sdCapsule` (for ribs), `sdTorus`, and warped `sdSphere`. The void ocean is rendered using fractional Brownian motion (fBm) layered on the ray hits. Time is passed through a fractional glitch function to generate the temporal stream artifacts.

### Mouse Interaction
The mouse directly rotates the camera view around the leviathan (simulating an orbital drone observation) and repels the temporal streams slightly from the cursor point.

### Color Mapping / Shading
A deep oceanic palette ranging from deep abyssal blue to intense cyan and neon purple for the plasma streams. The cyber-skeletal ribs use a subsurface scattering approximation with a high refraction index mapped to the `zoom_params` uniform.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Ethereal Cyber-Chrono Void-Whale
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Plasma Density, y=Temporal Glitch, z=Refraction Index, w=Core Bloom
    ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```

Parameters (for UI sliders)

Plasma Density (0.5, 0.0, 1.0, 0.01)
Temporal Glitch (0.2, 0.0, 1.0, 0.01)
Refraction Index (1.5, 1.0, 3.0, 0.05)
Core Bloom (0.8, 0.0, 2.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
