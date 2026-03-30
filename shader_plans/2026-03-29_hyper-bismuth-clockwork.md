# New Shader Plan: Hyper-Bismuth Clockwork

## Overview
A relentlessly grinding, infinite geometric mechanism built entirely of iridescent, square-stepped bismuth crystals that unfold and interlock like a cosmic clockwork engine.

## Features
- **Stepped Crystalline Geometry:** Raymarching procedural cubic fractals to simulate the natural, sharp stairstep growth of bismuth crystals.
- **Audio-Reactive Clockwork:** Crystals slide, rotate, and snap into place along rigid grid axes, driven by the audio beat accumulator (`u.config.y`).
- **Iridescent Thin-Film Interference:** Surfaces display intense, metallic rainbow iridescence, shifting dynamically based on the viewing angle and surface normal.
- **Infinite Domain Interlocking:** The entire structure repeats endlessly, creating a labyrinth of meshing gears and moving platforms.
- **Deep Geometric Shadows:** Heavy ambient occlusion and stark, hard-edged shadows emphasize the sharp, mechanical nature of the crystals.
- **Magnetic Singularity Cursor:** The mouse cursor acts as a localized magnetic distortion, pulling the stepped structures apart to reveal a glowing, molten core beneath the machinery.

## Technical Implementation
- File: public/shaders/gen-hyper-bismuth-clockwork.wgsl
- Category: generative
- Tags: ["mechanical", "crystal", "iridescent", "audio-reactive", "raymarching", "SDF"]
- Algorithm: Raymarching with domain repetition, Box SDFs, Boolean intersections for stairstep carving, and angular rotation matrices.

### Core Algorithm
Uses a repeated space where each cell contains a stack of progressively smaller Box SDFs, combined via `smin` and boolean operations to create hollow, stepped pyramidal structures. A KIFS (Kaleidoscopic Iterated Function System) on a cubic grid creates the branching, right-angled growth typical of bismuth.

### Mouse Interaction
The mouse (`u.zoom_config.y`, `u.zoom_config.z`) generates a localized spherical gravity well. As the ray approaches this coordinate, the grid domain is radially offset, causing the tightly interlocked crystals to split apart, exposing a highly emissive, bright white volumetric core.

### Color Mapping / Shading
Instead of a standard albedo, the color is derived from the dot product of the view vector and the surface normal (`dot(V, N)`), mapped through a multi-phase cosine palette (thin-film interference) to produce vibrant, metallic bands of pink, cyan, gold, and blue. Ambient occlusion is sampled heavily from the crevices.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Hyper-Bismuth Clockwork
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
    zoom_params: vec4<f32>,  // x=Complexity, y=Clock Speed, z=Iridescence, w=Grid Density
    ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```

## Parameters (for UI sliders)
- Complexity (default: 3.0, min: 1.0, max: 8.0, step: 0.1)
- Clock Speed (default: 1.0, min: 0.0, max: 5.0, step: 0.1)
- Iridescence (default: 1.0, min: 0.1, max: 3.0, step: 0.05)
- Grid Density (default: 2.0, min: 1.0, max: 5.0, step: 0.1)

## Integration Steps
- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
