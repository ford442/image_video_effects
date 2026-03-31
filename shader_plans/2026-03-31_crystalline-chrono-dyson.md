# New Shader Plan: Crystalline Chrono-Dyson

## Overview
A colossal, self-assembling Dyson sphere constructed of hyper-refractive crystal panels and flowing plasma conduits that orbit and extract energy from a dying, audio-reactive micro-quasar.

## Features
- Endless orbital camera fly-through of an evolving, multi-layered megastructure.
- Hyper-refractive crystal panels that distort and diffract background starlight.
- Central micro-quasar with volumetric, audio-driven plasma jets.
- Magnetic flux tubes connecting panels, rippling with energy pulses.
- Orbiting swarms of autonomous drones using particle-like flocking via domain repetition.
- Subsurface glowing conduits that pulse rhythmically to the audio frequency.

## Technical Implementation
- File: public/shaders/gen-crystalline-chrono-dyson.wgsl
- Category: generative
- Tags: ["cosmic", "mechanical", "refraction", "plasma", "raymarching"]
- Algorithm: Raymarching combined with domain repetition, KIFS for panel generation, and volumetric raymarching for the central quasar and jets.

### Core Algorithm
The megastructure is generated using spherical domain repetition and boolean intersections between nested spheres and KIFS-fractalized cutouts. The central quasar uses smooth-min combined with volumetric FBM noise driven by audio reactivity (`u.config.y`).

### Mouse Interaction
Mouse movement (`u.zoom_config.y`, `u.zoom_config.z`) controls the camera's orbital inclination and focal point. A gravity-well warp factor is applied to the ray origin and direction based on distance to the cursor, distorting the drone flight paths and panel alignment.

### Color Mapping / Shading
Glass panels use chromatic dispersion (sampling multiple wavelengths). The plasma jets use a multi-step gradient from deep ultraviolet to blinding white-gold based on density and audio-reactivity.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Crystalline Chrono-Dyson
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
    zoom_params: vec4<f32>,  // x=Panel Density, y=Quasar Glow, z=Flux Speed, w=Swarm Count
    ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```

## UI Parameters
### Parameters (for UI sliders)

Name (default, min, max, step)
- Panel Density (4.0, 1.0, 10.0, 0.1)
- Quasar Glow (1.5, 0.0, 5.0, 0.05)
- Flux Speed (1.0, 0.1, 3.0, 0.01)
- Swarm Count (50.0, 10.0, 100.0, 1.0)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-03-31_crystalline-chrono-dyson.md" "Crystalline Chrono-Dyson"
Reply with only: "✅ Plan created and queued: 2026-03-31_crystalline-chrono-dyson.md"
