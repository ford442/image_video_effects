# New Shader Plan: Prismatic Cyber-Auroral Manta-Swarm

## Overview
A majestic, hyper-dimensional ocean of auroral plasma where a synchronized swarm of glowing, cyber-organic manta rays glide and ripple in perfect unison with deep ambient acoustic bass drops.

## Features
- Volumetric cyber-auroral deep space fluid dynamics
- Flocking and synchronized motion of neon-lit manta ray structures
- Bioluminescent plasma trails fading over time
- Intricate geometry that responds to audio frequencies (bass drops causing massive auroral waves)
- Refractive glass-like bodies for the manta rays with subsurface chromatic scattering
- Real-time mouse interactions generating gravity wells to alter the swarm's path
- Fractal turbulence noise defining the auroral fluid medium

## Technical Implementation
- File: public/shaders/gen-prismatic-cyber-auroral-manta-swarm.wgsl
- Category: generative
- Tags: ["aurora", "swarm", "organic", "cyber", "plasma", "audio-reactive"]
- Algorithm: Boids-based flocking combined with fractal Simplex noise and raymarched volumetric plasma.

### Core Algorithm
Uses a hybrid approach of a compute-like boids algorithm simulated within the fragment shader (or utilizing ping-pong buffers if needed, but driven mainly by parametric noise and audio history) coupled with a volumetric raymarcher to render the auroral fog. The manta rays are modeled using analytical SDFs (smooth union of flattened spheres and wings defined by sine/cosine waves).

### Mouse Interaction
The mouse cursor acts as an intense gravity well (formula: `force = normalize(mouse_pos - boid_pos) / pow(length(mouse_pos - boid_pos) + 0.1, 2.0)`), pulling the manta rays into a beautiful whirlpool spiral before they break formation.

### Color Mapping / Shading
Uses a highly chromatic metallic subsurface scattering model. Colors map from deep neon indigo to brilliant cyan and magenta based on audio input, with intense bloom on the leading edges of the wings.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Prismatic Cyber-Auroral Manta-Swarm
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Shatter Threshold, y=Chime Density, z=Refraction Index, w=Transmission
    ripples: array<vec4<f32>, 50>,
};

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

// SDFs and Noise
fn sdf_manta(p: vec3<f32>, time: f32) -> f32 {
    // Basic manta SDF implementation
    return length(p) - 1.0;
}
```

Parameters (for UI sliders)
- "Swarm Cohesion" (0.5, 0.0, 1.0, 0.01)
- "Aurora Intensity" (0.8, 0.0, 2.0, 0.05)
- "Audio Reactivity" (1.0, 0.0, 5.0, 0.1)

Integration Steps
- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
