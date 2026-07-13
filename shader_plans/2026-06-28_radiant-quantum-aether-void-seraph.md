# New Shader Plan: Radiant Quantum-Aether Void-Seraph

## Overview
A hyper-majestic, six-winged biomechanical celestial entity forged from woven aether-plasma and liquid-chrome, hovering endlessly within a chaotic quantum-storm void while its bioluminescent wings fold and expand in direct response to acoustic frequencies.

## Features
- **Six-Winged Fractal Geometry:** Uses advanced rotational mirroring and recursive folding to create six distinct, morphing cyber-angelic wings.
- **Woven Aether-Plasma Feathers:** Volumetric raymarching of noise-displaced SDFs forms shimmering, semi-transparent plasma "feathers" that ripple.
- **Liquid-Chrome Core:** The central entity features a highly reflective, metallic subsurface that warps ambient cosmic lighting.
- **Acoustic Wing Dynamics:** Ambient bass frequencies physically drive the wing-span spread and the pulsation of the plasma feathers.
- **Quantum-Storm Void:** The background is a dense, volumetric field of fractured particle storms and glowing cosmic dust.
- **Chrono-Distortion Halo:** A halo of time-distorted fractal math floating above the core, rotating asynchronously based on high-frequency audio.

## Technical Implementation
- File: public/shaders/gen-radiant-quantum-aether-void-seraph.wgsl
- Category: generative
- Tags: ["organic", "quantum", "cosmic", "mechanical", "audio-reactive"]
- Algorithm: Raymarching with domain-repeated, rotationally symmetrical SDFs and volumetric density accumulation.

### Core Algorithm
The shader will employ a standard raymarching loop for the central entity and a secondary volumetric pass for the background storm. The Seraph is constructed using an initial sphere SDF for the liquid-chrome core, surrounded by six rotationally instanced wing structures. The wings use domain warping (via 3D fBM noise) and recursive scaling to simulate interlocking feathers. A global acoustic uniform scales the expansion multiplier of the rotation matrices controlling the wing spread.

### Mouse Interaction
Mouse movement dictates the "gravity well" of the entity. The (x,y) coordinates map to a spatial displacement vector that subtly pulls the core and warps the space around it, using a formula like `warp = max(0.0, 1.0 - length(p.xy - mouse.xy) * 2.0) * mouse_intensity;`. This introduces a drag effect on the wings as the camera tracks the Seraph.

### Color Mapping / Shading
The core uses a standard PBR-inspired liquid-chrome shading model, sampling an ambient environment gradient for reflection. The wings utilize subsurface scattering approximation and additive blending with a dual-tone palette (radiant gold to deep aether-blue). A bloom pass (simulated via glowing density accumulation along the ray path) emphasizes the bioluminescence of the wings and the halo.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Radiant Quantum-Aether Void-Seraph
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
    resolution: vec2<f32>,
    mouse: vec2<f32>,
    config: vec4<f32>,
    zoom_params: vec4<f32>,
    mouse_buttons: vec4<f32>,
    time: f32,
    audio_freq: f32,
};

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ... Additional helper functions, SDFs, and Raymarching logic ...
// ...
```

## Parameters (for UI sliders)

- Wing Expansion (0.5, 0.0, 1.0, 0.01)
- Plasma Density (0.7, 0.0, 2.0, 0.05)
- Chrome Reflectivity (0.8, 0.0, 1.0, 0.01)
- Void Chaos (0.3, 0.0, 1.0, 0.05)

## Integration Steps

1. Create shader file `public/shaders/gen-radiant-quantum-aether-void-seraph.wgsl`
2. Create JSON definition in `shader_definitions/generative/gen-radiant-quantum-aether-void-seraph.json`
3. Run `generate_shader_lists.js`
4. Upload via `storage_manager`
