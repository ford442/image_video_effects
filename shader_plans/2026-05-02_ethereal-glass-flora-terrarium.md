# New Shader Plan: Ethereal Glass-Flora Terrarium

## Overview
A hyper-detailed, translucent macroscopic greenhouse where impossible glass botanicals bloom, pulsing with neon nectar that reacts dynamically to ambient audio frequencies.

## Features
- Procedurally generated L-system-inspired glass branches with organic curves and crystalline refractions.
- Subsurface scattered bioluminescent nectar flowing through the hollow stems, driven by audio bass.
- Soft-shadowed, atmospheric fog trapped inside the infinite terrarium container.
- Iridescent petals that dynamically unfold and fold back based on the beat and time.
- Gravity-defying pollen particles that orbit the flora and interact with mouse gravity wells.

## Technical Implementation
- File: public/shaders/gen-ethereal-glass-flora-terrarium.wgsl
- Category: generative
- Tags: ["organic", "glass", "bioluminescent", "audio-reactive", "raymarching"]
- Algorithm: Raymarching combined with generalized organic folding, subsurface scattering, and particle-based pollen.

### Core Algorithm
Raymarching an SDF scene utilizing smooth minimums (smin) and domain repetition with twist and bend operators to simulate organic growth. A pseudo L-system is approximated via folding operations (KIFS modified with spherical folds) to create the branching structures. The nectar flow is modeled via traveling waves along the SDF gradients mapped to time and audio inputs.

### Mouse Interaction
The mouse cursor acts as a localized gravity well and light source. Pollen particles (simulated via 2D point rendering overlaid or baked into the volume) swarm towards the mouse, and the glass flora stems bend subtly towards the screen-space coordinate.

### Color Mapping / Shading
Glass refraction and dispersion via chromatic aberration (sampling different indices of refraction for RGB channels). The nectar utilizes an emissive glow driven by the `plasmaBuffer` or neon palettes (cyan to magenta). Soft directional lighting and volumetric fog add depth and atmospheric scattering.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Ethereal Glass-Flora Terrarium
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
    ripples: array<vec4<f32>, 50>
};

// Set up globals and core utility functions
fn sdGlassFlora(p: vec3<f32>) -> f32 {
    // Folding and bending logic for organic glass structures
    return length(p) - 1.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let coords = vec2<i32>(id.xy);
    let res = textureDimensions(writeTexture);
    if (coords.x >= i32(res.x) || coords.y >= i32(res.y)) { return; }

    // Raymarching, lighting, and refraction logic
    let color = vec4<f32>(1.0);
    textureStore(writeTexture, coords, color);
}
```

Parameters (for UI sliders)

Flora Density (5.0, 1.0, 10.0, 0.1)
Nectar Glow (2.0, 0.0, 5.0, 0.1)
Refraction Index (1.5, 1.0, 2.5, 0.01)
Time Warp (1.0, 0.1, 3.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
