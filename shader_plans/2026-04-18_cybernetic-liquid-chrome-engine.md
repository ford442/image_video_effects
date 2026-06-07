# New Shader Plan: Cybernetic Liquid-Chrome Engine

## Overview
A colossal, endlessly shifting mechanical engine constructed of hyper-reflective liquid chrome, pumping iridescent plasma through infinitely complex fractal pistons that react to the heavy bass of audio frequencies.

## Features
- Infinite, raymarched array of interlocking mechanical pistons and gears.
- Smooth min (smin) blending creates a 'liquid chrome' organic-mechanical aesthetic.
- Audio-reactive displacement where bass frequencies (`u.config.y`) drive the piston pumping speed and expansion.
- Iridescent plasma conduits that pulse with light, featuring chromatic dispersion.
- Real-time environmental reflections on the chrome surfaces based on ray normals.
- Mouse interaction controls the camera's rotational orbit and depth of field focus.

## Technical Implementation
- File: public/shaders/gen-cybernetic-liquid-chrome-engine.wgsl
- Category: generative
- Tags: ["mechanical", "liquid-metal", "audio-reactive", "raymarching", "fractal"]
- Algorithm: Raymarching with domain repetition, smooth-minimum boolean operations, and KIFS folding for intricate mechanical details.

### Core Algorithm
- Uses `opRep` (domain repetition) to create an infinite array of engine blocks.
- Employs `smin` for boolean unions between cylinder and box SDFs, resulting in fluid metal joints.
- Applies KIFS (Kaleidoscopic Iterated Function System) folding on the inner core to generate micro-circuitry and gears.
- Time `u.config.x` combined with Audio `u.config.y` drives the vertical translation of piston SDFs.

### Mouse Interaction
- `u.zoom_config.y` and `u.zoom_config.z` are mapped to 2D rotation matrices for the camera's Ray Origin (`ro`) and Ray Direction (`rd`).
- Panning the mouse shifts the perspective around the central plasma core, revealing deeper layers of the engine.

### Color Mapping / Shading
- The chrome material uses the normal vector to sample a procedural cubemap/gradient, achieving high specularity and environmental reflections.
- The plasma core uses accumulated emissive coloring (glow) based on the distance to the SDF surface, scaling intensity with `u.zoom_params.z`.
- Chromatic aberration is applied at the edges of the screen during high audio amplitude.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Cybernetic Liquid-Chrome Engine
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
    zoom_params: vec4<f32>,  // x=Engine Speed, y=Chrome Reflectivity, z=Plasma Glow, w=Complexity
    ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```

Parameters (for UI sliders)

Engine Speed (1.0, 0.1, 5.0, 0.1)
Chrome Reflectivity (0.8, 0.0, 1.0, 0.05)
Plasma Glow (2.0, 0.0, 10.0, 0.1)
Complexity (3.0, 1.0, 8.0, 1.0)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-04-18_cybernetic-liquid-chrome-engine.md" "Cybernetic Liquid-Chrome Engine"
Reply with only: "✅ Plan created and queued: 2026-04-18_cybernetic-liquid-chrome-engine.md"
