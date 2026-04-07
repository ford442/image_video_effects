# New Shader Plan: Chromodynamic Plasma-Collider

## Overview
A hyper-speed journey down an infinite magnetic containment tunnel where sub-atomic particles collide and shatter into vibrant, audio-reactive showers of exotic matter.

## Features
- Infinite raymarched tunnel of polished obsidian magnetic rings and glowing plasma tracks.
- High-speed particle system simulating sub-atomic collisions that burst into chromatic sparks.
- Roaring plasma containment fields that react violently to audio frequencies.
- Relativistic speed distortion where the tunnel warps and bends in 4D space.
- Mouse interaction acts as a magnetic anomaly, pulling the particle streams toward the cursor and causing localized shockwaves.

## Technical Implementation
- File: public/shaders/gen-chromodynamic-plasma-collider.wgsl
- Category: generative
- Tags: ["cosmic", "mechanical", "particle", "plasma", "audio-reactive"]
- Algorithm: Raymarched infinite tunnel with domain repetition, combined with high-frequency intersecting SDF streams, and FBM-driven volumetric plasma.

### Core Algorithm
- **Geometry:** Raymarching a cylindrical tunnel with radial and longitudinal domain repetition to create the segmented magnetic containment rings.
- **Collisions:** A secondary pass or integrated SDF calculating high-frequency particle streaks intersecting at the center of the ring, blooming into localized starbursts using smooth-min functions.
- **Plasma Fields:** Volumetric FBM noise evaluated along the edges of the tunnel to simulate the glowing containment energy. Audio input (`u.config.y`) spikes the FBM amplitude and particle velocity.

### Mouse Interaction
- The mouse (`u.zoom_config.yz`) shifts the center of the magnetic field. Raymarched coordinates are distorted radially towards the mouse position, creating a localized gravity well that bends the particle streams and warps the containment rings.

### Color Mapping / Shading
- **Rings:** High specularity obsidian, utilizing environment mapping approximations for glossy reflections.
- **Particles:** Neon chromatic dispersion (magenta, cyan, blinding yellow) mimicking Cherenkov radiation and exotic matter decays.
- **Plasma:** Deep blues and purples fading into brilliant white at high densities.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Chromodynamic Plasma-Collider
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Ring Density, y=Collision Rate, z=Anomaly Pull, w=Tunnel Warp
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// ... SDFs, FBM, Raymarching Loop, Main Compute ...

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // Implement raymarching and rendering here
}
```

## UI Parameters
Parameters (for UI sliders)

Name (default, min, max, step)
- Ring Density (15.0, 5.0, 30.0, 1.0) -> mapped to `u.zoom_params.x`
- Collision Rate (5.0, 0.5, 20.0, 0.5) -> mapped to `u.zoom_params.y`
- Anomaly Pull (1.0, 0.0, 5.0, 0.1) -> mapped to `u.zoom_params.z`
- Tunnel Warp (0.5, 0.0, 2.0, 0.05) -> mapped to `u.zoom_params.w`

## Integration Steps
- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
