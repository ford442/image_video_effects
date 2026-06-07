# New Shader Plan: Quantum-Fluorescent Aether-Moth Swarm

## Overview
A hyper-dense, glowing swarm of ethereal quantum 'moths' that dynamically flock and self-organize into luminous geometric mandalas, reacting violently to acoustic frequencies.

## Features
- Millions of tiny glowing moth-like particles simulated via continuous noise fields.
- Emergent flocking behavior mimicking complex fluid dynamics and swarming algorithms.
- Audio-reactive fluorescence, where particle colors shift rapidly based on ambient sound intensity.
- Interactive gravity nodes that attract or scatter the swarm based on mouse proximity.
- Spontaneous self-assembly into intricate, temporary geometric mandalas when audio thresholds are met.

## Technical Implementation
- File: public/shaders/gen-quantum-fluorescent-aether-moth-swarm.wgsl
- Category: generative
- Tags: ["swarm", "fluorescent", "quantum", "moth", "audio-reactive", "interactive"]
- Algorithm: Boids-style flocking behavior driven by curl noise, modulated by SDF-based attractors and audio reactivity.

### Core Algorithm
A dual-pass simulation. The first pass computes velocity vectors using 3D simplex curl noise, updating particle positions stored in a persistent buffer (ping-pong textures). The second pass renders the particles, applying an additive blending bloom effect to simulate bright fluorescent trails.

### Mouse Interaction
The mouse acts as a high-mass gravitational anomaly. Left-clicking temporarily reverses the polarity, violently scattering the swarm outward in a spherical shockwave. The exact distortion formula calculates distance to the mouse coordinate, applying an inverse-square force weighted by `zoom_config.y` and `zoom_config.z`.

### Color Mapping / Shading
Particles emit HDR colors based on their current velocity and age. High-speed movement maps to bright cyan and magenta, while slower drift transitions to deep ultraviolet and indigo. An ambient bloom pass will create the illusion of glowing quantum plasma.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Quantum-Fluorescent Aether-Moth Swarm
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

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Swarm Density, y=Curl Intensity, z=Glow Strength, w=Audio Sensitivity
    ripples: array<vec4<f32>, 50>,
};

// ... (Simplex Noise Functions)
// ... (Flocking Logic)
// ... (Main Render Pass)

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // ... logic
}
```

## Parameters (for UI sliders)
- Swarm Density (1.0, 0.1, 5.0, 0.1)
- Curl Intensity (0.5, 0.0, 2.0, 0.05)
- Glow Strength (2.0, 0.5, 10.0, 0.1)
- Audio Sensitivity (1.0, 0.0, 3.0, 0.1)

## Integration Steps
1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
