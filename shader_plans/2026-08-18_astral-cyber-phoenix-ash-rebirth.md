# New Shader Plan: Astral Cyber-Phoenix Ash-Rebirth

## Overview
A hyper-dynamic fractal pyre where incandescent plasma feathers collapse into quantum ash and immediately reignite into a majestic cyber-phoenix silhouette. The aesthetic is pure digital rebirth: searing solar oranges, iridescent magenta sparks, and deep void-space indigo cooling down to geometric ash-particles.

## Features
- **Reignition Cycle:** Periodic collapse of the structure into ash using domain-warped curl noise, followed by an explosive outward reformation.
- **Incandescent Plumes:** Raymarched volume rendering of flame-like SDF structures with variable density.
- **Cyber-Feathers:** Sharp, geometric Voronoi patterns embedded within the flames, giving a structured, digital feel to the organic fire.
- **Quantum Ash Trails:** Audio-reactive particles (using dataTextureC) that follow the mouse, simulating burning embers caught in a vortex.
- **Thermal Bloom Gradient:** Extreme HDR shading where the core shifts from white-hot to solar orange, fading to cooling magenta and void-black.

## Technical Implementation
- File: public/shaders/gen-astral-cyber-phoenix-ash-rebirth.wgsl
- Category: generative
- Tags: ["fractal", "fire", "plasma", "rebirth", "cyber", "audio-reactive"]
- Algorithm: Raymarching an SDF of stacked, noise-distorted cones and spheres, blended with domain-warped curl noise for the ash effect.

### Core Algorithm
The base SDF is an avian-like structure made of smooth-min blended capsules and stretched spheres. To simulate fire, this SDF is displaced heavily using layered 3D value noise. The "rebirth cycle" is driven by a `fract(u.config.x * cycle_speed)` timer, which aggressively increases the noise amplitude and scales the base SDF down, breaking it into disconnected fragments (ash) before snapping back. The cyber-feathers are an overlay of 3D Voronoi edges applied as a subtractive boolean operation.

### Mouse Interaction
The mouse acts as a gravitational heat vortex. The distance to `u.zoom_config.yz` modifies the noise distortion field, pulling the flames towards the cursor. When `u.zoom_config.w` (mouse down) is active, it intensifies the heat, multiplying the color intensity and expanding the SDF volume.

### Color Mapping / Shading
Uses a multi-stop color gradient mapped to the SDF distance and raymarching step count. Core (close to SDF): `vec3(1.0, 0.9, 0.6)` (White-hot). Mid-flame: `vec3(1.0, 0.4, 0.0)` (Solar Orange). Edges: `vec3(0.6, 0.0, 0.8)` (Magenta). Void/Ash: `vec3(0.05, 0.05, 0.1)` (Indigo). The audio input from `dataTextureC` slightly modulates the intensity of the mid-flame.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Astral Cyber-Phoenix Ash-Rebirth
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
  zoom_params: vec4<f32>,  // .x = Rebirth Speed, .y = Flame Intensity, .z = Cyber Complexity, .w = Ash Dispersion
  ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
// ... additional helper functions for noise, voronoi, sdf, raymarching, and coloring.
```

Parameters (for UI sliders)

Rebirth Speed (0.5, 0.1, 2.0, 0.01)
Flame Intensity (1.0, 0.1, 3.0, 0.05)
Cyber Complexity (0.5, 0.0, 1.0, 0.05)
Ash Dispersion (0.4, 0.0, 1.0, 0.05)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
