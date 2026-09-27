# New Shader Plan: Aethereal Ferrofluid Chrono-Core

## Overview
A hyper-magnetic temporal liquid entity that pulses and spikes to an unseen quantum beat, blending dark metallic spikes with internal bioluminescent ethereal light.

## Features
- Dynamic ferrofluid spikes driven by 4D noise
- Subsurface scattering effect for internal illumination
- Audio-reactive temporal shifts altering the liquid's viscosity
- Mouse-driven magnetic anomaly dragging the fluid spikes
- Iridescent oil-slick interference patterns on the spikes
- Smooth organic blending using polynomial smooth min
- Raymarching with fake ambient occlusion for depth

## Technical Implementation
- File: public/shaders/gen-aethereal-ferrofluid-chrono-core.wgsl
- Category: generative
- Tags: ["ferrofluid", "organic", "magnetic", "bioluminescent", "liquid"]
- Algorithm: Raymarching an SDF sphere displaced by multi-layered 4D Simplex noise and Voronoi noise, with smooth min operations for organic spikes and temporal distortion based on audio/time.

### Core Algorithm
A central SDF sphere is the base geometry. It is heavily displaced using a combination of smooth Voronoi noise (for the spike bases) and 4D Simplex noise (for temporal flow). The displacement amplitude and frequency are modulated by `u.zoom_params.x` (viscosity) and `u.zoom_params.y` (spike density). The overall SDF uses `smin` to create the gooey, liquid metal behavior between the spikes and the main body.

### Mouse Interaction
The mouse acts as a powerful magnetic dipole. `u.zoom_params.z` controls the magnetic strength. When the mouse moves, the SDF is distorted towards the mouse vector, pulling the ferrofluid into a large, elongated gravity well that stretches the local spikes.

### Color Mapping / Shading
The surface uses a dark, glossy metallic BRDF-like shading, heavily tinted by an iridescent palette `hue2rgb` based on the normal and view vector dot product (Fresnel). The inner valleys of the displacement map are tinted with a bright bioluminescent glow (cyan/magenta) simulating subsurface scattering, powered by fake ambient occlusion and SDF thickness estimation.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Aethereal Ferrofluid Chrono-Core
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// Helper functions (rot2D, hash, noise, smin, etc.)

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(p: vec3<f32>) -> f32 {
    // SDF mapping logic with noise and mouse magnetic distortion
    return 0.0;
}

// Raymarching, Normal calc, AO, Shading

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // ... setup uv, ray origin, ray direction
    // ... raymarch loop
    // ... apply color and writeTexture
}
```

Parameters (for UI sliders)
- Viscosity (default: 0.5, min: 0.1, max: 1.0, step: 0.01) - mapped to `u.zoom_params.x`
- Spike Density (default: 0.6, min: 0.0, max: 2.0, step: 0.01) - mapped to `u.zoom_params.y`
- Magnetic Strength (default: 0.5, min: 0.0, max: 1.0, step: 0.01) - mapped to `u.zoom_params.z`
- Bioluminescence (default: 0.8, min: 0.0, max: 2.0, step: 0.01) - mapped to `u.zoom_params.w`
