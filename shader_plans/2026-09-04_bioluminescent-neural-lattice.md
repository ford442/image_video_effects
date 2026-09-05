# New Shader Plan: Bioluminescent Neural Lattice

## Overview
A mesmerizing, pulsating web of deep-sea neural pathways that crackles with bioluminescent energy.

## Features
- Ethereal, organic 3D volumetric rendering via raymarching
- Branching neural structures generated with Voronoi and domain repetition
- Dynamic energy pulses that travel along the synaptic pathways
- Subtle subsurface scattering and chromatic aberration for a liquid environment feel
- Audio-reactive synaptic flashes on low frequencies
- Mouse interaction acts as an attractive chemical gradient, bending the neural structures

## Technical Implementation
- File: public/shaders/gen-bioluminescent-neural-lattice.wgsl
- Category: generative
- Tags: ["organic", "bioluminescence", "volumetric", "neural", "audio-reactive"]
- Algorithm: Raymarching through a perturbed, domain-repeated Voronoi field representing organic cellular structures, with accumulated emissive glow based on distance to the edges.

### Core Algorithm
Uses a raymarching loop over a signed distance field (SDF). The base structure is a 3D Voronoi network (using a cellular noise approximation) that is domain-repeated to create an infinite lattice. Smooth min functions (`smin`) blend the branches together to look like organic tissue. We map the volume accumulation to distance to the SDF surface for a soft glow.

### Mouse Interaction
The mouse coordinates act as an attractive chemical gradient. The ray direction and origin are subtly warped towards the mouse's projected world-space position, distorting the lattice and concentrating the bioluminescent energy density around the cursor.

### Color Mapping / Shading
Background is a dark oceanic void (`vec3(0.01, 0.05, 0.1)`). Rays accumulate color at each step based on the inverse distance to the neural branches. The accumulated glow maps through a cosine palette shifting from deep cyan to electric blue and magenta, simulating bioluminescence.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Bioluminescent Neural Lattice
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
  zoom_params: vec4<f32>,  // .x = Point Density, .y = Rotation Speed, .z = Point Size, .w = Color Shift
  ripples: array<vec4<f32>, 50>,
};

// ... Constants, noise functions, SDF functions ...

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  // Raymarching logic here
}
```

Parameters (for UI sliders)
- Zoom Params X: Synapse Density (1.0, 0.1, 5.0, 0.1)
- Zoom Params Y: Pulse Speed (1.0, 0.1, 3.0, 0.1)
- Zoom Params Z: Glow Intensity (1.0, 0.0, 2.0, 0.1)
- Zoom Params W: Color Shift (0.0, 0.0, 1.0, 0.01)
