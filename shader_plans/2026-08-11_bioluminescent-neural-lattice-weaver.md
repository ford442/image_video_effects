# New Shader Plan: Bioluminescent Neural-Lattice Weaver

## Overview
A hyper-organic network of glowing synaptic tendrils growing through a crystalline data lattice, pulsing with chaotic energetic rhythm.

## Features
- Infinite 3D fractal neural branching
- Smooth organic metaball integration between nodes
- Crystalline geometric structural lattice background
- High-frequency bioluminescent pulse rippling along branches
- Mouse-driven gravity well that bends and refracts the lattice
- Volumetric depth fog that reacts to energetic pulses
- Subsurface scattering on thicker organic structures

## Technical Implementation
- File: public/shaders/gen-bioluminescent-neural-lattice-weaver.wgsl
- Category: generative
- Tags: ["organic", "lattice", "bioluminescence", "neural", "crystalline"]
- Algorithm: Raymarching through a hybrid SDF combining domain-repeated crystalline geometries (octahedrons) with smooth-min organic noise pathways simulating fungal/neural growth.

### Core Algorithm
- Use 3D Simplex noise mixed with domain folding to create a primary lattice framework.
- Raymarch a smooth-min (`smin`) composition of spheres and capsules driven by 3D noise (FBM) to simulate interconnected neural pathways.
- Use the intersection of the organic shapes and geometric lattice to trigger energy pulses.

### Mouse Interaction
- Mouse acts as an energetic gravity well.
- `let mouse = u.zoom_config.yz;` drives a local spatial distortion function (e.g. `p += normalize(p - mouse_pos) * (1.0 / length(p - mouse_pos)) * strength;`) within the raymarching loop, pulling the neural pathways towards the cursor.

### Color Mapping / Shading
- Deep background is a volumetric abyss (cyan/magenta mix).
- The crystalline lattice uses a metallic, specular material model.
- The neural pathways use subsurface scattering approximations (soft rim lighting + transmitted light).
- Energy pulses use intense HDR bloom mapping (electric blue and bright orange).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Bioluminescent Neural-Lattice Weaver
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

// ... (full skeleton with comments)

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
  let coords = vec2<i32>(id.xy);
  let resolution = vec2<f32>(u.config.z, u.config.w);
  let uv = vec2<f32>(coords) / resolution;

  // Implementation
  let out_color = vec4<f32>(uv, 0.5, 1.0);
  textureStore(writeTexture, coords, out_color);
}
```

## Parameters (for UI sliders)

- Synapse Density (1.5, 0.1, 5.0, 0.1)
- Growth Speed (1.0, 0.0, 3.0, 0.1)
- Lattice Hardness (0.8, 0.0, 1.0, 0.05)
- Bioluminescence Intensity (2.0, 0.0, 5.0, 0.1)
