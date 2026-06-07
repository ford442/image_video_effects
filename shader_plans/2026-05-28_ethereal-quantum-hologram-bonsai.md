# New Shader Plan: Ethereal Quantum-Hologram Bonsai

## Overview
A serene, hyper-dimensional bonsai tree woven entirely from shimmering quantum hard-light, its branches continuously fracturing and self-assembling in a state of tranquil probabilistic super-position.

## Features
- Intricate, recursive L-system branching structures simulated via continuous noise and SDF geometries.
- Leaves composed of floating quantum 'droplets' that orbit their respective branches.
- Holographic glitch and chromatic aberration effects shimmering along the bark based on audio frequencies.
- Mouse interaction acting as a 'quantum gardener', pruning or encouraging growth through gravitational lensing.
- Fluid-like spatial anomalies rippling through the roots when audio bass peaks.

## Technical Implementation
- File: public/shaders/gen-ethereal-quantum-hologram-bonsai.wgsl
- Category: generative
- Tags: ["bonsai", "hologram", "quantum", "l-system", "audio-reactive", "interactive"]
- Algorithm: Raymarching against recursive volumetric SDFs combined with curled simplex noise for spatial displacement.

### Core Algorithm
A 3D raymarching simulation where the primary SDF is a recursive cylinder hierarchy mimicking L-system growth. Domain repetition and rotation matrices offset the branches. A high-frequency simplex curl noise acts as a displacement field on the SDF to give it a digital, fluid-like holographic instability.

### Mouse Interaction
The mouse acts as a localized spatial warp. Clicking creates a temporal vortex (gravity well) that gently pulls branches and floating droplets towards the cursor, using an inverse-square distance formula weighted by `zoom_config.y` and `zoom_config.z`.

### Color Mapping / Shading
Branches are rendered with a translucent holographic aesthetic using iridescent gradients mapping from deep jade to luminous magenta. Glinting specularity highlights the edges of the SDFs, while an additive blend pass simulates the ambient glow of the quantum leaves.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Ethereal Quantum-Hologram Bonsai
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// ... (Noise Functions)
// ... (Rotation & Domain Repetition)
// ... (SDF L-System Geometry)
// ... (Raymarching & Shading)

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // ... logic
}
```

## Parameters (for UI sliders)
- Branch Complexity (4.0, 1.0, 7.0, 1.0)
- Hologram Instability (0.5, 0.0, 2.0, 0.05)
- Ambient Glow (2.0, 0.5, 10.0, 0.1)
- Audio Reactivity (1.0, 0.0, 3.0, 0.1)

## Integration Steps
1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
