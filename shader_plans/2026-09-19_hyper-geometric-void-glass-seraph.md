# New Shader Plan: Hyper-Geometric Void-Glass Seraph

## Overview
A hyper-dimensional entity of shattered, iridescent glass revolving around a central void singularity, folding space and time into sharp geometric fractals.

## Features
- Evolving 4D tesseract structures folded into 3D space
- Iridescent void-glass rendering with chromatic aberration
- A central gravitational singularity that bends light
- Audio-reactive shattering and crystalline growth
- Infinite domain repetition mapped to non-euclidean geometry
- Bioluminescent highlights on glass fracture edges

## Technical Implementation
- File: public/shaders/gen-hyper-geometric-void-glass-seraph.wgsl
- Category: generative
- Tags: ["fractal", "glass", "tesseract", "chromatic", "geometry"]
- Algorithm: Raymarching through a folded space-time metric with KIFS (Kaleidoscopic IFS) fractals and ray refraction.

### Core Algorithm
The core utilizes a Kaleidoscopic Iterated Function System (KIFS) to generate sharp, intersecting geometric planes that resemble shattered glass. A custom distance estimator applies multiple spatial folds and rotations driven by time. The domain space is warped to create a pseudo-4D projection effect. A central void singularity is modeled using a negative SDF sphere that inverts space and dramatically bends the raymarching paths around it.

### Mouse Interaction
The mouse acts as an orientation and folding controller. `zoom_config.yz` directs the global rotation of the KIFS fractal, allowing the user to tumble the entire structure. The distance to the mouse cursor dynamically modulates the fold angles, causing the glass shards to compress or expand based on proximity.

### Color Mapping / Shading
The shading model simulates iridescent glass. Normal vectors are used to compute a fake Schlick approximation for fresnel reflections and refractions. Chromatic aberration is simulated by splitting the color calculation into RGB channels with slight spatial offsets. The edges of the geometry are highlighted with a glowing electric cyan or magenta based on the iteration count from the fractal folding process.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Hyper-Geometric Void-Glass Seraph
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
  zoom_params: vec4<f32>,  // .x = Folding Scale, .y = Glass Refraction, .z = Singularity Mass, .w = Chromatic Aberration
  ripples: array<vec4<f32>, 50>,
};

// ... shader logic continues
```

Parameters (for UI sliders)

Folding Scale (1.5, 0.5, 3.0, 0.05) - mapped to zoom_params.x
Glass Refraction (0.8, 0.1, 2.0, 0.05) - mapped to zoom_params.y
Singularity Mass (1.0, 0.0, 5.0, 0.1) - mapped to zoom_params.z
Chromatic Aberration (0.5, 0.0, 1.0, 0.01) - mapped to zoom_params.w