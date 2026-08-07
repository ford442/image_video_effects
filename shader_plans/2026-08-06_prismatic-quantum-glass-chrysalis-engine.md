# New Shader Plan: Prismatic Quantum-Glass Chrysalis-Engine

## Overview
A hyper-reflective, slowly rotating multifaceted chrysalis floating in a void of refracted auroral light, combining harsh geometric cuts with fluid internal luminescence.

## Features
- Multifaceted SDF chrysalis core with sharp geometric cuts
- Internal volumetric "liquid plasma" lighting mapping to mouse input
- Refractive index simulation using multi-sample raymarching bounces
- Chromatic aberration trails driven by temporal decay buffers
- Procedural geometric cracking and reforming animations over time

## Technical Implementation
- File: public/shaders/gen-prismatic-quantum-glass-chrysalis-engine.wgsl
- Category: generative
- Tags: ["chrysalis", "glass", "quantum", "refraction", "chromatic"]
- Algorithm: Raymarching with domain-folded internal reflection surfaces and chromatic displacement

### Core Algorithm
Using a combination of sdOctahedron and sdHexPrism intersected and carved by 3D Voronoi noise to create a jagged, multifaceted gem-like structure. The raymarcher will implement a secondary bounce loop, where entering the SDF calculates a refracted internal ray, tracking depth until it exits, to simulate a thick glass/quantum medium.

### Mouse Interaction
The mouse `zoom_config.yz` will dictate the localized gravity well of the internal liquid plasma, pulling the brightest volumetric emissions towards the cursor position mapped into 3D space, and increasing the rotational velocity of the inner core structure based on proximity.

### Color Mapping / Shading
A high-contrast aesthetic where the exterior is cool, deep space void colors (blues, blacks, deep purples), while the interior uses extreme HDR emissive gradients of fiery gold, magenta, and cyan (plasma colors). Thin film iridescence on the glass surface is calculated via Fresnel equations multiplied by the normal vector.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Prismatic Quantum-Glass Chrysalis-Engine
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ... constants and helpers

fn rot(a: f32) -> mat2x2<f32> {
  let s = sin(a);
  let c = cos(a);
  return mat2x2<f32>(c, -s, s, c);
}

// ... SDFs
fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
  var q = abs(p);
  return (q.x + q.y + q.z - s) * 0.57735027;
}

// ... Raymarching loop
// ... Shading and post-processing
```

## Parameters (for UI sliders)
- Refraction Index (1.5, 1.0, 2.5, 0.01)
- Plasma Intensity (1.0, 0.0, 3.0, 0.1)
- Core Rotation Speed (0.5, 0.0, 2.0, 0.01)
- Chromatic Dispersion (0.2, 0.0, 1.0, 0.01)
