# New Shader Plan: Celestial Nanite-Swarm Nebula

## Overview
A majestic, slowly churning nebula constructed entirely from trillions of glowing, synchronized nanites that dynamically self-assemble into intricate, shifting geometric constellations and colossal architectural megastructures in deep space.

## Features
- Volumetric Nanite-Fog rendering using advanced raymarching and layered noise.
- Dynamic Self-Assembly of geometric shapes (hypercubes, tetrahedrons) from the swarm.
- Audio-reactive constellation links that flash and pulse with neon-plasma energy.
- Cosmic Wind distortions driving fluid-like swarm dynamics.
- High-frequency chromatic aberration mimicking microscopic lens flares.
- Deep space parallax background with shifting dark matter voids.
- Interactive mouse-driven gravity wells that disrupt and pull the nanite structures.

## Technical Implementation
- File: public/shaders/gen-celestial-nanite-swarm-nebula.wgsl
- Category: generative
- Tags: ["cosmic", "particle-system", "geometric", "audio-reactive", "nanites"]
- Algorithm: Raymarching with volumetric accumulation, Voronoi noise, and SDF-based swarm density clustering.

### Core Algorithm
Utilizes a modified volumetric raymarcher where density is defined by a combination of 3D Voronoi noise (to simulate individual nanite clusters) and geometric SDFs (to form the architectural shapes). The noise field is advected over time to simulate cosmic winds, while audio frequencies threshold the density to create sudden, violent structural formations.

### Mouse Interaction
The mouse acts as a localized gravity singularity. Its coordinates are mapped to the 3D space, heavily warping the SDF domain and creating a swirling vortex effect in the noise field, pulling the nanite clusters into a tight orbital accretion disk.

### Color Mapping / Shading
A deep, moody color palette of bioluminescent cyan, vivid magenta, and stark gold. The volumetric lighting uses a phase function to create backlighting effects from an implied central star, with heavy bloom applied to dense nanite clusters and a subtle subsurface scattering approximation.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Celestial Nanite-Swarm Nebula
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
// ... (full skeleton with comments)

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Swarm Density, y=Constellation Link, z=Wind Speed, w=Geometric Order
    ripples: array<vec4<f32>, 50>,
};

// SDFs and Noise functions
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += vec3<f32>(dot(q, q.yxz + vec3<f32>(33.33)));
    return fract((q.xxy + q.yxx) * q.zyx);
}

// Volume Density Function
fn map_density(p: vec3<f32>) -> f32 {
    // Volume generation logic...
    return 0.0;
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // Main raymarching loop...
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Swarm Density (0.5, 0.0, 1.0, 0.01)
- Constellation Link (0.3, 0.0, 1.0, 0.01)
- Wind Speed (0.2, 0.0, 1.0, 0.01)
- Geometric Order (0.7, 0.0, 1.0, 0.01)

Integration Steps

1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
