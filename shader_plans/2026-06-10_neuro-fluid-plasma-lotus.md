# New Shader Plan: Neuro-Fluid Plasma-Lotus

## Overview
A majestic, hyper-organic lotus flower suspended in a zero-gravity void, blooming endlessly with translucent, liquid-neon neuro-fluid petals that physically morph and ripple with bioluminescent plasma in perfect sync with ambient cosmic frequencies.

## Features
- Procedural generation of overlapping, transparent petals using spherical domain warping and 3D Simplex noise.
- Audio-reactive blooming mechanics where bass frequencies (`u.config.y`) drive the expansion and unfurling of the outer petals.
- Volumetric inner core emitting a concentrated beam of swirling plasma, simulated using multi-octave fBm.
- Liquid-neon material properties simulating subsurface scattering and chromatic dispersion across the neuro-fluid petals.
- Dynamic magnetic distortion field that gently twists the entire lotus geometry based on an evolving time variable (`u.config.x`).
- Slow, cinematic camera rotation providing a continuous orbit around the glowing anomaly.
- Deep abyss background with subtle, iridescent dust particles drifting through the volumetric lighting.

## Technical Implementation
- File: public/shaders/gen-neuro-fluid-plasma-lotus.wgsl
- Category: generative
- Tags: ["organic", "floral", "plasma", "audio-reactive", "liquid-neon"]
- Algorithm: Volumetric SDF raymarching. The lotus is constructed from deformed intersecting spheres mapped onto a polar coordinate system to mimic overlapping petals, combined with dense noise fields for the glowing stamen core.

### Core Algorithm
The geometry is primarily driven by a custom SDF that combines a base sphere with intense sinusoidal and noise-based displacement along spherical coordinates to create petal-like ridges. The interior consists of a smaller, intensely glowing sphere displaced by 3D fractional Brownian motion (fBm). The entire domain is smoothly twisted along the Y-axis.

### Mouse Interaction
The mouse (`u.zoom_config.y`, `u.zoom_config.z`) dynamically offsets the center of gravity of the lotus, causing the petals to reach towards the cursor like phototropic alien flora.

### Color Mapping / Shading
The petals utilize a complex gradient mapped from deep violet/magenta at the base to piercing electric cyan/neon pink at the tips. Shading incorporates Schlick's approximation for a glossy, wet sheen, while the inner core acts as a primary light source injecting pure white-hot energy outward, simulating intense subsurface scattering.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Neuro-Fluid Plasma-Lotus
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
    zoom_params: vec4<f32>,  // x=Petal Curl, y=Bloom Pulse, z=Core Heat, w=Dispersion
    ripples: array<vec4<f32>, 50>,
};

// ... (Functions: SDFs, Noise, Raymarching, Shading...)
```

Parameters (for UI sliders)

Name (default, min, max, step)
Petal Curl (1.5, 0.5, 3.0, 0.1)
Bloom Pulse (1.0, 0.1, 2.5, 0.1)
Core Heat (2.0, 1.0, 5.0, 0.1)
Dispersion (1.2, 0.5, 2.5, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
