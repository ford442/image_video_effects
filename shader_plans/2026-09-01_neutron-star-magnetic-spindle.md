# New Shader Plan: Neutron-Star Magnetic Spindle

## Overview
A violently spinning, extremely dense singularity core emitting intensely twisted magnetic field lines and glowing volumetric plasma arcs that bend space and time.

## Features
- Dense, highly refractive ray-marched singularity core with intense gravity lensing.
- Volumetric plasma spindles twisting along polar magnetic field axes.
- Relativistic Doppler beaming causing asymmetrical color and intensity shifts.
- Dynamic particle accretion disk swirling around the equatorial plane.
- Audio-reactive magnetic flux lines that pulse and destabilize with low frequencies.

## Technical Implementation
- File: public/shaders/gen-neutron-star-magnetic-spindle.wgsl
- Category: generative
- Tags: ["space", "plasma", "volumetric", "singularity", "raymarching"]
- Algorithm: Raymarching combined with domain twisting, volumetric integration for plasma jets, and fBM for accretion disk density.

### Core Algorithm
Uses a raymarching loop with SDFs for the central sphere and toroids for the accretion disk. The space around the sphere is twisted using a rotation matrix dependent on the distance from the core to simulate frame-dragging. Volumetric rendering is layered on top by sampling density functions along the ray, colored via a blackbody palette.

### Mouse Interaction
Mouse movement shifts the perspective (orbiting the star) and adjusts the intensity of the polar magnetic jets, allowing the user to view the relativistic effects from different angles.

### Color Mapping / Shading
The core uses intense metallic/plasma shading (pure white to deep purple). The accretion disk and jets use a temperature-based color mapping (blackbody radiation gradient from deep reds/oranges up to blinding blue/white), with intense bloom added to simulate immense energy output.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Neutron-Star Magnetic Spindle
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Core Density, .y = Spin Rate, .z = Jet Intensity, .w = Disk Scale
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// SDFs, raymarching, and rendering logic go here...

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<i32>(global_id.xy);
    if (f32(coords.x) >= resolution.x || f32(coords.y) >= resolution.y) {
        return;
    }

    // UV space
    let uv = vec2<f32>(coords) / resolution;

    // Main compute logic here

    let color = vec4<f32>(uv, 0.5, 1.0); // Placeholder
    textureStore(writeTexture, coords, color);
}
```

## Parameters (for UI sliders)
- Core Density (1.0, 0.1, 5.0, 0.1)
- Spin Rate (1.0, 0.0, 3.0, 0.1)
- Jet Intensity (1.5, 0.0, 5.0, 0.1)
- Disk Scale (1.0, 0.5, 3.0, 0.1)
