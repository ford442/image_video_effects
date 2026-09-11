# New Shader Plan: Hyperdimensional Plasma Loom

## Overview
A mesmerizing tangle of iridescent energy threads weaving themselves into complex, higher-dimensional geometric topologies, creating the illusion of cosmic fabric being spun in real-time.

## Features
- Real-time physics simulation of quantum strings using iterative domain twisting.
- Four-dimensional noise-driven thread topology that evolves continuously over time.
- Dynamic gravity wells driven by cursor interaction, pulling and distorting the plasma loom.
- Volumetric color mapping with deep, iridescent hues mimicking metallic bismuth and ionized gas.
- High-frequency spatial repetition folded through smooth min/max SDF blending to create intricate woven patterns.
- Temporal blending for soft glowing trails, adding to the silk-like quality.

## Technical Implementation
- File: public/shaders/gen-hyperdimensional-plasma-loom.wgsl
- Category: generative
- Tags: ["cosmic", "quantum", "abstract", "geometric", "strands"]
- Algorithm: Raymarching combined with domain repetition and iterative 4D noise sampling to create woven volumetric strands.

### Core Algorithm
The shader uses a raymarching approach over a domain twisted by multiple octaves of 4D simplex-like noise. The space is divided using polar repetition to form a lattice of strings. The core SDF evaluates distance to an array of interlocked helices (the "loom threads"). These distances are softly blended using exponential min (smin) to create junctions where threads merge and diverge dynamically.

### Mouse Interaction
The mouse acts as a localized gravitational singularity. It warps the coordinate space locally before the raymarching step, effectively sucking the plasma threads into a spiraling vortex around the cursor. The distortion follows an inverse-square falloff formula based on the distance to the mapped mouse position.

### Color Mapping / Shading
Color is driven by normal and view vectors relative to a dynamic lighting direction, simulating thin-film interference. We'll map a base iridescent gradient (deep violets, electric blues, and vivid magentas) and blend in a high-intensity bloom pass when threads cluster densely, mimicking plasma discharge.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Hyperdimensional Plasma Loom
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
  zoom_params: vec4<f32>,  // .x = Weave Density, .y = Thread Thickness, .z = Plasma Intensity, .w = Time Speed
  ripples: array<vec4<f32>, 50>,
};

// ... constants and helper functions ...

// Main entry point
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let dims = vec2<i32>(textureDimensions(writeTexture));
  let coords = vec2<i32>(global_id.xy);
  if (coords.x >= dims.x || coords.y >= dims.y) {
    return;
  }

  // Implementation details...

  textureStore(writeTexture, coords, vec4<f32>(0.0, 0.0, 0.0, 1.0));
}
```

Parameters (for UI sliders)

Weave Density (2.0, 0.5, 5.0, 0.1)
Thread Thickness (0.05, 0.01, 0.2, 0.01)
Plasma Intensity (1.0, 0.0, 3.0, 0.1)
Time Speed (1.0, 0.1, 3.0, 0.1)
