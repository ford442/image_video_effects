# New Shader Plan: Quantum-Chrome Serpent Ouroboros

## Overview
A hyper-dimensional, endlessly twisting serpentine ring forged of liquid-chrome and fractal dark matter that consumes its own geometric tail while weaving a tapestry of light across the void.

## Features
- Procedural generation of a seamlessly twisting, endless serpent using advanced tubular SDFs and toroidal domain warping.
- Dynamic audio-reactive scales formed from multi-layered KIFS fractals that flare and ripple with deep bass frequencies (`u.config.y`).
- Volumetric inner core emitting a concentrated beam of swirling quantum plasma, simulated using multi-octave fBm.
- Liquid-chrome material properties simulating hyper-reflective index and environment mapping distortion.
- Dynamic magnetic distortion field that gently twists the entire serpent geometry based on an evolving time variable (`u.config.x`).
- Slow, cinematic camera rotation providing a continuous orbit around the coiling metallic entity.
- Deep abyss background with subtle, iridescent dust particles drifting through the volumetric lighting.

## Technical Implementation
- File: public/shaders/gen-quantum-chrome-serpent-ouroboros.wgsl
- Category: generative
- Tags: ["metallic", "serpent", "fractal", "audio-reactive", "liquid-chrome"]
- Algorithm: Volumetric SDF raymarching. The serpent is constructed from a distorted torus SDF that loops endlessly, with scales and ridges created by mapped KIFS fractals and 3D Simplex noise.

### Core Algorithm
The geometry is primarily driven by a custom SDF that combines a base torus with intense sinusoidal and noise-based displacement along toroidal coordinates to create scale-like ridges. The interior consists of an intensely glowing plasma core displaced by 3D fractional Brownian motion (fBm). The entire domain is smoothly twisted along the axis of the torus.

### Mouse Interaction
The mouse (`u.zoom_config.y`, `u.zoom_config.z`) dynamically alters the local gravity vector, causing the serpent to warp and reach toward the cursor while maintaining its continuous loop.

### Color Mapping / Shading
The scales utilize a complex reflective gradient mapped from deep abyssal blacks to piercing silver and neon cyan at the tips. Shading incorporates Schlick's approximation for a hyper-reflective metallic sheen, while the inner core acts as a primary light source injecting pure white-hot energy outward, simulating intense subsurface scattering through the gaps in the scales.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Quantum-Chrome Serpent Ouroboros
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Coil Tightness, y=Scale Density, z=Core Heat, w=Dispersion
    ripples: array<vec4<f32>, 50>,
};

// ... (Functions: SDFs, Noise, Raymarching, Shading...)
```

Parameters (for UI sliders)

Name (default, min, max, step)
Coil Tightness (1.5, 0.5, 3.0, 0.1)
Scale Density (1.0, 0.1, 2.5, 0.1)
Core Heat (2.0, 1.0, 5.0, 0.1)
Dispersion (1.2, 0.5, 2.5, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
