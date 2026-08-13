# New Shader Plan: Luminescent Quantum-Silicate Diatom

## Overview
A hyper-detailed, microscopic journey into a living quantum silicate organism, where crystalline structures pulse with bioluminescent energy and fold through higher dimensions.

## Features
- **Quantum Silicate Lattice**: A repeating, crystalline domain-folded structure representing the diatom's shell.
- **Bioluminescent Pulsing**: Subsurface scattering and internal emission that reacts dynamically to time and spatial coordinates.
- **Fluid Cytoplasm**: A fluidic interior noise field simulating the flow of quantum cytoplasm.
- **Micro-cellular Gravity Wells**: Interaction points that distort the structural lattice and attract luminous particles.
- **Chromatic Diffraction**: Iridescent shading that mimics light splitting through microscopic silica.
- **Organic Asymmetry**: Noise-driven perturbation applied to perfect SDFs to create organic, biological imperfections.

## Technical Implementation
- File: public/shaders/gen-luminescent-quantum-silicate-diatom.wgsl
- Category: generative
- Tags: ["microscopic", "organic", "crystalline", "quantum", "bioluminescent"]
- Algorithm: Raymarching a complex SDF with domain repetition, combined with volumetric accumulation for the cytoplasm and subsurface scattering approximations for the shell.

### Core Algorithm
The core is a raymarching loop evaluating a signed distance field. The SDF combines a base primitive (e.g., an octahedron or dodecahedron for the shell) mapped with high-frequency 3D Voronoi noise to carve out the intricate pores typical of diatoms. Domain folding (`p = p - spacing * round(p / spacing)`) is used on a larger scale to create a colony or continuous lattice. A secondary raymarching pass (or volumetric accumulation inside the main loop) samples a turbulent 3D simplex noise to render the fluid interior.

### Mouse Interaction
The mouse cursor (`u.zoom_config.yz`) acts as a micro-cellular gravity well. It introduces a localized spatial distortion in the domain folding: `p += normalize(p - mouse_pos) * (strength / (length(p - mouse_pos) + 0.1))`. This pulls the lattice and the fluidic noise towards the interaction point, simulating a physical perturbation in the microscopic medium.

### Color Mapping / Shading
Shading utilizes a multi-layered approach. The outer silicate shell employs a custom iridescent BRDF, blending base color with a chromatic aberration gradient based on the viewing angle (fresnel). The inner cytoplasm accumulates color based on noise density, using a vibrant bioluminescent palette (cyan, magenta, and electric blue). A final post-processing step (within the shader) applies a soft bloom to the emissive parts to emphasize the radiant energy.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Luminescent Quantum-Silicate Diatom
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

// ... (full skeleton with comments)

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }
    let uv = vec2<f32>(f32(global_id.x), f32(global_id.y)) / resolution;

    // Core raymarching and shading logic here

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(1.0));
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Pore Density (0.5, 0.1, 1.0, 0.01) - Mapped to `zoom_params.x`
- Pulse Speed (0.2, 0.0, 1.0, 0.01) - Mapped to `zoom_params.y`
- Iridescence Spread (0.4, 0.0, 1.0, 0.01) - Mapped to `zoom_params.z`
- Bioluminescence Shift (0.5, 0.0, 1.0, 0.01) - Mapped to `zoom_params.w`

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
