# New Shader Plan: Abyssal Silicate Geode-Weaver

## Overview
A crystalline, deep-sea geological formation that slowly weaves iridescent silicate threads over sharp geode facets, reacting organically to acoustic interactions.

## Features
- Intricate volumetric raymarching of crystalline geode cavities.
- Iridescent subsurface scattering emulation using color mapping over depth gradients.
- Slowly morphing silicate thread structures formed by domain-warped gyroid noise.
- Acoustic reactivity driving the glow and pulsing intensity of the internal crystal facets.
- Mouse interaction that acts as a gravity well, gently bending the silicate threads towards the cursor.

## Technical Implementation
- File: public/shaders/gen-abyssal-silicate-geode-weaver.wgsl
- Category: generative
- Tags: ["crystal", "geode", "iridescent", "organic", "audio-reactive", "raymarching"]
- Algorithm: Volumetric raymarching with domain-warped gyroid noise for silicate threads and a faceted Voronoi basis for the geode structure.

### Core Algorithm
Raymarching an SDF that combines a hollowed-out sphere with Voronoi cellular structures to create sharp, crystalline geode facets. Inside the geode, an organic web of silicate threads is generated using domain-warped gyroid noise (sin(x)*cos(y) + sin(y)*cos(z) + sin(z)*cos(x)), animated slowly over time. The SDFs are smoothly blended using `smin` to allow the threads to anchor organically to the geode walls.

### Mouse Interaction
The mouse cursor position (`u.zoom_config.yz`) is converted into 3D space as a gentle gravity well. The domain of the gyroid noise is warped by drawing coordinates slightly towards the mouse vector, causing the silicate threads to bend and reach towards the user's interaction point.

### Color Mapping / Shading
Shading employs pseudo-subsurface scattering. Ray penetration depth into the crystal facets drives a palette map transitioning from deep abyssal blues and purples to bright, luminescent teal and magenta along the edges. The silicate threads use an iridescent gradient mapped to the view angle (fresnel).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Abyssal Silicate Geode-Weaver
// Category: generative
// ----------------------------------------------------------------
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

## Parameters (for UI sliders)

Thread Density (1.0, 0.1, 3.0, 0.1)
Geode Facet Scale (2.5, 0.5, 5.0, 0.1)
Iridescence Intensity (0.8, 0.0, 1.0, 0.05)
Acoustic Glow (1.5, 0.0, 5.0, 0.1)
