# New Shader Plan: Chromodynamic Glass Labyrinth

## Overview
A hyper-reflective, endlessly unfolding non-Euclidean maze of liquid glass that refracts a shifting spectrum of chromodynamic light.

## Features
- Infinite non-Euclidean spatial folding via domain repetition and Moebius transformations.
- Physically based glass refraction simulating chromatic aberration and caustic-like highlights.
- Dynamic color phase-shifting based on spatial depth and time.
- Smooth raymarched SDFs featuring intricate geometric labyrinth structures.
- Interactive perspective manipulation and structural warping via mouse input.

## Technical Implementation
- File: public/shaders/gen-chromodynamic-glass-labyrinth.wgsl
- Category: generative
- Tags: ["raymarching", "glass", "refraction", "non-euclidean", "chromodynamic", "labyrinth"]
- Algorithm: Raymarching through a domain-folded space with an SDF defining thick, rounded glass panels, utilizing multi-tap refraction and dispersion for coloring.

### Core Algorithm
The scene uses a raymarching loop over a Signed Distance Field (SDF). The space is folded using `mod()` functions and rotational symmetry to create an endless labyrinth. The SDF primitive is a heavily rounded box subtracted by intersecting spheres to form organic openings. A secondary pass or analytical calculation estimates internal refraction by bending the ray based on the surface normal and computing a secondary color map.

### Mouse Interaction
Mouse movement (when actively clicked) controls a dynamic gravity well that spatially distorts the domain space around the focal point. The x-axis drives a global rotation of the labyrinth structure, while the y-axis controls the index of refraction and structural expansion, warping the glass corridors in real-time.

### Color Mapping / Shading
Lighting is driven by an image-based lighting (IBL) approximation using layered cosine gradients to simulate a vibrant, chromodynamic environment. The material features high specular reflections, fresnel-based edge glowing, and chromatic dispersion where different color channels refract at slightly varying angles, creating a rainbow edge effect.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Chromodynamic Glass Labyrinth
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
  zoom_params: vec4<f32>,  // .x = Structural Density, .y = Refraction Index, .z = Dispersion, .w = Chromatic Phase
  ripples: array<vec4<f32>, 50>,
};

// ... constants and helpers (e.g., rot2D, SDF primitives) ...

// ... map function for labyrinth SDF ...
fn map(p: vec3<f32>) -> f32 {
    // Spatial folding and domain repetition
    // SDF geometry implementation
    return 0.0;
}

// ... normal calculation ...

// ... raymarching function ...

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // 1. Calculate UVs
    // 2. Setup camera and ray direction
    // 3. Raymarch the scene
    // 4. Calculate lighting, reflection, and refraction
    // 5. Output to writeTexture and writeDepthTexture
}
```

Parameters (for UI sliders)

- Structural Density (2.0, 0.5, 5.0, 0.1)
- Refraction Index (1.5, 1.0, 3.0, 0.05)
- Dispersion (0.05, 0.0, 0.2, 0.01)
- Chromatic Phase (0.0, 0.0, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
