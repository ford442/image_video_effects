# New Shader Plan: Galactic Aether-Crystal Geode-Core

## Overview
A hyper-dimensional, slowly rotating cosmic geode cracked open to reveal a pulsating, audio-reactive core of liquid aether-plasma and infinitely recursive chrono-crystals.

## Features
- Intricate volumetric KIFS fractals generating the jagged inner crystalline structures.
- A swirling, liquid-plasma core that erupts with bioluminescent light in sync with acoustic frequencies.
- High-refraction "chrono-glass" outer shell that warps background cosmic starlight.
- Dynamic internal glowing atmospheric scattering (volumetric fog) representing trapped quantum gas.
- Intricate subsurface scattering effects mimicking glowing cosmic minerals.

## Technical Implementation
- File: public/shaders/gen-galactic-aether-crystal-geode-core.wgsl
- Category: generative
- Tags: ["crystal", "geode", "cosmic", "volumetric", "fractal", "plasma"]
- Algorithm: Raymarching a complex boolean SDF combining an outer spherical hull with internal KIFS fractal crystal growths, featuring a highly dispersive volumetric interior lighting model.

### Core Algorithm
- Primary SDF is a sphere intersected with 3D voronoi/cellular noise to create the cracked opening.
- Inside the hollow core, KIFS (Kaleidoscopic Iterated Function Systems) are used to generate dense, sharp crystalline formations.
- A central sphere SDF uses FBM (Fractal Brownian Motion) domain warping to simulate the liquid aether-plasma core.
- Raymarching loop includes volumetric accumulation for the trapped glowing quantum gas.

### Mouse Interaction
- Mouse X/Y rotates the entire geode structure, allowing the user to peer deep into the crystalline core.
- Clicking or holding amplifies the crystal refraction index and speeds up the plasma core's internal fluid motion.

### Color Mapping / Shading
- Crystals use physical refraction approximations with chromatic aberration.
- The plasma core emits a dual-tone glowing gradient (e.g., deep magenta to cyan) that intensifies with audio (using `u.config.y`).
- The outer shell resembles dark, matte cosmic rock with subtle metallic highlights.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Galactic Aether-Crystal Geode-Core
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
    zoom_params: vec4<f32>,  // x=Crystal Density, y=Core Glow, z=Fractal Iterations, w=Gas Density
    ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```

## Parameters (for UI sliders)

- Crystal Density (1.0, 0.1, 3.0, 0.1) maps to `u.zoom_params.x`
- Core Glow (1.5, 0.0, 5.0, 0.1) maps to `u.zoom_params.y`
- Fractal Iterations (5.0, 1.0, 10.0, 1.0) maps to `u.zoom_params.z`
- Gas Density (0.5, 0.0, 2.0, 0.05) maps to `u.zoom_params.w`

## Integration Steps

1. Create shader file `public/shaders/gen-galactic-aether-crystal-geode-core.wgsl`
2. Create JSON definition `shader_definitions/generative/gen-galactic-aether-crystal-geode-core.json`
3. Run `node scripts/generate_shader_lists.js`
4. Upload via `storage_manager`
