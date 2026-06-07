# New Shader Plan: Bioluminescent Aether-Pulsar

## Overview
A rapidly spinning, hyper-dimensional neutron star forged from glowing quantum fluid, ejecting spiraling, audio-reactive beams of liquid light that rhythmically warp the surrounding spacetime lattice.

## Features
- Colossal, smooth-min blended fluid pulsar core that throbs and distorts with audio frequencies.
- Spiraling, volumetric emission beams that sweep across the domain, illuminating the void.
- A warped, surrounding accretion disk of hyper-refractive silica debris and plasma.
- Spacetime lattice distortion effects (domain warping) driven by the pulsar's rotation.
- Bioluminescent, chromatic color mapping with deep abyssal blues and vibrant neon purples.

## Technical Implementation
- File: public/shaders/gen-bioluminescent-aether-pulsar.wgsl
- Category: generative
- Tags: ["cosmic", "quantum", "fluid", "audio-reactive", "raymarching"]
- Algorithm: Raymarching with smooth-min blending for the fluid core, domain-warped SDFs for the accretion debris, and volumetric ray accumulation for the emission beams.

### Core Algorithm
The base SDF is a sphere modified by 3D noise and twisted using a 3D rotation matrix dependent on the y-axis to create the pulsar core. An intersecting torus, broken up by cellular noise and KIFS folds, forms the accretion disk. The beams are rendered via volumetric accumulation during the raymarch, sampling the distance to a twisting cylinder. Audio reactivity (`u.config.y`) is injected into the rotation matrices and noise amplitudes.

### Mouse Interaction
The mouse (`u.zoom_config.y`, `u.zoom_config.z`) controls the camera orbit and pitch, allowing the user to view the pulsar from directly above the emission poles or along the chaotic accretion plane.

### Color Mapping / Shading
The core uses a base of deep abyssal blue transitioning into bright cyan and neon purple at the poles where the beams emit. The beams themselves use additive blending and high-intensity chromatic values. The debris disk features thin-film interference (iridescence) and subsurface scattering to simulate glowing glass interacting with the pulsar's light.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Bioluminescent Aether-Pulsar
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
    zoom_params: vec4<f32>,  // x=Pulsar Spin Rate, y=Beam Intensity, z=Accretion Density, w=Color Shift
    ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments for hash, noise, SDFs, raymarching, and coloring)
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Pulsar Spin Rate (1.0, 0.1, 5.0, 0.1)
- Beam Intensity (0.8, 0.0, 2.0, 0.05)
- Accretion Density (0.5, 0.0, 1.0, 0.05)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
