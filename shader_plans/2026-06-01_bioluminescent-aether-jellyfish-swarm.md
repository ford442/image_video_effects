# New Shader Plan: Bioluminescent Aether-Jellyfish Swarm

## Overview
A mesmerizing, hyper-organic deep-space ocean teeming with a swarm of ethereal, semi-transparent jellyfish woven from luminous aether-plasma that propel themselves rhythmically in sync with ambient sonic frequencies.

## Features
- Ethereal, translucent bell geometries mathematically sculpted using smooth min operators and dynamic SDFs.
- Trailing tentacles constructed from fractal noise curves that respond fluidly to simulated ocean currents and mouse interactions.
- A volumetric, bioluminescent subsurface scattering effect giving the jellyfish a deep, glowing core.
- Audio-reactive propulsion rhythms and vibrant color shifts pulsing through the nervous systems of the swarm.
- A slowly shifting, refractive deep-space liquid background mimicking a cosmic abyss.
- Dynamic clustering behavior allowing jellyfish to subtly flock and avoid each other using localized proximity checks.
- Interactive gravity wells that gently push or pull the swarm via mouse influence.

## Technical Implementation
- File: public/shaders/gen-bioluminescent-aether-jellyfish-swarm.wgsl
- Category: generative
- Tags: ["organic", "swarm", "fluid", "volumetric", "audio-reactive"]
- Algorithm: Raymarching combined with domain repetition and fluid vector field distortion for tentacle physics.

### Core Algorithm
- Use raymarching to render the central bells using `sdCapsule` and `sdSphere` combinations, blended softly using `smin`.
- Employ domain repetition (`mod` equivalent logic) to instance the swarm, slightly offsetting phase and scale based on cell ID.
- Use 3D simplex noise to perturb the surface of the bells, creating organic, breathing movement over time.

### Mouse Interaction
- The mouse acts as a localized hydrodynamic repulsor or attractor.
- Distance from the mouse to the cell center is used to push jellyfish away, scaling down the effect exponentially with distance.
- `velocity += normalize(jelly_pos - mouse_pos) * (1.0 / (1.0 + distance(jelly_pos, mouse_pos) * 10.0))`

### Color Mapping / Shading
- Deep bioluminescent colors (cyans, purples, bioluminescent greens) mapped using an audio-driven gradient palette.
- Simulated subsurface scattering: map thickness to light transmission using the inverse dot product of the normal and the view direction (`pow(1.0 - max(dot(N, V), 0.0), 3.0)`).
- Bloom pass simulation via smooth attenuation of the alpha channel near the bell edges.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Bioluminescent Aether-Jellyfish Swarm
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

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

// Parameters (for UI sliders)
// Swarm Density (10.0, 1.0, 30.0, 1.0)
// Propulsion Speed (1.0, 0.1, 5.0, 0.1)
// Bioluminescence Intensity (2.0, 0.5, 10.0, 0.1)
// Tentacle Length (5.0, 1.0, 15.0, 0.5)

// ... (full skeleton with comments)
```

## Integration Steps
- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
