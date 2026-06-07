# New Shader Plan: Resonant Quantum-Obsidian Scarab-Engine

## Overview
A hyper-organic biomechanical engine constructed from sleek, interlocking plates of liquid obsidian and glowing quantum circuitry that functions like a colossal scarab breathing and reacting to acoustic energy.

## Features
- Intricate KIFS fractal-based exoskeleton shifting organically.
- Subsurface scattering effect simulating light beneath obsidian.
- Audio-reactive plasma pulses flowing through the circuitry.
- Dynamic glowing core that dilates and expands with low-frequency beats.
- Hovering, magnetic quantum-dust particles orbiting the central engine.
- Interactive mouse gravity that warps the scarab's temporal field.

## Technical Implementation
- File: public/shaders/gen-resonant-quantum-obsidian-scarab-engine.wgsl
- Category: generative
- Tags: ["biomechanical", "fractal", "obsidian", "audio-reactive", "quantum"]
- Algorithm: Raymarching combined with domain repetition and fractal folding to generate biomechanical carapaces.

### Core Algorithm
Uses spherical domain repetition and iterated KIFS (Kaleidoscopic Iterated Function Systems) folds to generate the layered, overlapping plates of the scarab engine. A modified Torus SDF acts as the pulsing core, heavily modulated by audio.

### Mouse Interaction
A secondary gravity well. As the mouse moves, the spatial domain bends towards the cursor, warping the obsidian plates using a smooth exponential falloff function.

### Color Mapping / Shading
A mix of deep specular reflections (using Schlick's approximation for obsidian) and vivid emissive plasma. The plasma color gradients transition from deep violet to searing cyan based on the SDF distance to the glowing circuitry channels.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Resonant Quantum-Obsidian Scarab-Engine
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// ... Raymarching and SDF functions to be implemented here ...

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // Boilerplate raymarching setup...
}
```

## Parameters (for UI sliders)
- Exoskeleton Complexity (4.0, 1.0, 10.0, 0.1)
- Plasma Intensity (1.5, 0.0, 5.0, 0.05)
- Obsidian Reflectivity (0.8, 0.0, 1.0, 0.01)
- Core Pulse Rate (2.0, 0.1, 10.0, 0.1)
- Quantum Dust Density (50.0, 10.0, 200.0, 1.0)

## Integration Steps
- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
