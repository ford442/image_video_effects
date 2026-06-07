# New Shader Plan: Hyper-Refractive Rain-Matrix

## Overview
An infinite, falling matrix of hyper-refractive liquid-metal raindrops suspended in a dark quantum storm, distorting reality as they collide, merge, and shatter to the rhythm of unseen bass frequencies.

## Features
- Endlessly falling, highly dense rain matrix utilizing domain repetition.
- Liquid-metal metaballs that smoothly merge on contact via smooth-min blending.
- Audio-reactive drop size, speed, and collision intensity.
- Deep, pseudo-refractive background distortion simulating a reality-bending storm.
- Interactive mouse ripples that aggressively scatter and repel the falling droplets.

## Technical Implementation
- File: public/shaders/gen-hyper-refractive-rain-matrix.wgsl
- Category: generative
- Tags: ["liquid", "matrix", "rain", "refractive", "metaball", "audio-reactive"]
- Algorithm: Raymarching with heavily domain-repeated spheres and capsules, utilizing smooth-minimum for fluid dynamics and pseudo-refraction for the background.

### Core Algorithm
The environment is structured using domain repetition on the X and Z axes, with a continuous falling motion applied to the Y-axis. The base SDF consists of stretched capsules and spheres simulating raindrops. When these objects pass close to each other, a `smin` function merges their distance fields, creating a fluid tearing and combining effect. Audio (`u.config.y`) drives the falling speed and the stretch factor of the drops.

### Mouse Interaction
The mouse (`u.zoom_config.y`, `u.zoom_config.z`) generates an expanding shockwave or a localized gravity well. Droplets within the influence radius are aggressively pushed outward, their paths warped by an inverse-square distance falloff, creating a parting sea of liquid metal.

### Color Mapping / Shading
The drops utilize a high-contrast liquid metal look. The surface normal is used to fetch a severely distorted sample of a procedural environment map (generated via 3D noise). This pseudo-refraction bends the colors of the background storm (deep abyssal blue, electric cyan, and stark white) across the surface of the droplets. Highlights are sharply calculated via a modified Blinn-Phong model to simulate intense, focused light sources.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Hyper-Refractive Rain-Matrix
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // mapped to UI sliders
    ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments for hash, noise, SDFs, raymarching, and coloring)
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Rain Density (1.0, 0.1, 5.0, 0.1)
- Drop Speed (1.0, 0.0, 3.0, 0.1)
- Fluid Viscosity (0.5, 0.0, 1.0, 0.05)
- Storm Intensity (0.8, 0.0, 2.0, 0.05)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
