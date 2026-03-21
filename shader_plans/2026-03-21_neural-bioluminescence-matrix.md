# New Shader Plan: Neural Bioluminescence Matrix

## Overview
A pulsing, infinite organic matrix of glowing synthetic neurons firing quantum light impulses across a void, merging biological growth with cybernetic circuitry.

## Features
- Infinite 3D neuronal web using raymarching and domain warping.
- Pulsing quantum data packets traveling along branches, synced to audio/beats.
- Audio-reactive synapses that expand and flash on high amplitudes.
- Magnetic mouse repulsion that temporarily bends and stretches the neuronal network.
- Volumetric glowing fog and subsurface scattering to give a squishy, living organic feel.
- Slowly rotating camera that weaves through the neural matrix.

## Technical Implementation
- File: public/shaders/gen-neural-bioluminescence-matrix.wgsl
- Category: generative
- Tags: ["organic", "quantum", "matrix", "bioluminescence", "neural"]
- Algorithm: Raymarching with FBM-driven organic displacement and traveling wave pulses.

### Core Algorithm
Uses a raymarched base structure built from a highly warped 3D grid (domain repetition) of smooth-minimum connected capsules (SDFs) to form a continuous web. The structure is displaced by multi-octave 3D Simplex noise to create organic, root-like tendrils. Pulses are calculated using the dot product of the position and a traveling time-based wave vector.

### Mouse Interaction
The mouse acts as a localized repulsor field (gravity well logic inverted). It bends the local space of the SDF by displacing the `p` vector smoothly based on `length(p - mousePos)`, causing the neurons to stretch and avoid the cursor.

### Color Mapping / Shading
Deep void background with the matrix illuminated by cyan and magenta emissive pulses. The base material uses a dark, glossy subsurface scattering approximation, while the "synapses" have a strong additive bloom/glow that peaks when an audio proxy variable (`u.config.y`) pulses.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Neural Bioluminescence Matrix
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// --- Core SDFs & Noise ---
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let res = exp2(-k * a) + exp2(-k * b);
    return -log2(res) / k;
}

fn map(p: vec3<f32>) -> f32 {
    // Web construction logic with domain repetition and FBM
    return 1.0;
}

// --- Main Render Loop ---
@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let texSize = textureDimensions(writeTexture);
    let uv = vec2<f32>(id.xy) / vec2<f32>(texSize);

    // Raymarching logic...
    var color = vec4<f32>(0.0);

    // Mouse repulsion and audio pulse integration using u.config.y
    // ...

    textureStore(writeTexture, id.xy, color);
}
```

## Parameters (for UI sliders)
- Node Density (1.0, 0.1, 5.0, 0.1)
- Pulse Speed (1.0, 0.0, 5.0, 0.1)
- Audio Reactivity (1.0, 0.0, 2.0, 0.1)
- Bio-Glow Intensity (2.0, 0.0, 10.0, 0.1)

## Integration Steps
1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
