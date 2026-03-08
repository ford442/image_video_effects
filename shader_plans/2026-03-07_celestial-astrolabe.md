# New Shader Plan: Celestial Astrolabe

## Overview
A majestic, turning cosmic mechanism composed of nested brass rings and glowing glass lenses that map the movements of ethereal starfields.

## Features
- Nested, independently rotating metallic rings (astrolabe structure).
- Glowing, refractive glass lenses that distort the background starlight.
- Dynamic energy tethers connecting alignment points.
- Procedural starfield background with twinkling and colored nebulae.
- Interactive gravity wells influenced by mouse position.

## Technical Implementation
- File: public/shaders/gen-celestial-astrolabe.wgsl
- Category: generative
- Tags: ["3d", "raymarching", "cosmic", "clockwork", "glass", "brass", "astrolabe"]
- Algorithm: Raymarching with transparent materials, multi-pass approximations for refraction, and domain repetition for the starfield.

### Core Algorithm
- **SDFs**: Torus SDFs for the astrolabe rings, sphere/lens SDFs for the glass elements, cylinder SDFs for the energy tethers.
- **Transformations**: Time-based and coordinate-based rotations (modulo/parity) to create the independent turning of the rings.
- **Starfield**: Domain repetition (`opRep`) applied to small glowing spheres or noise-based points to create an infinite, glittering background.

### Mouse Interaction
- The mouse position (`u.zoom_config.yz`) acts as a localized gravity well.
- Formula: The SDF coordinates of the rings and stars are distorted by `dir * strength / distance(p, mouse_pos)`.
- It causes the astrolabe to slightly tilt and the star tethers to bend towards the cursor.

### Color Mapping / Shading
- **Brass**: Metallic shading with high specular highlights, slight roughness, and a golden/bronze gradient map based on surface normals.
- **Glass Lenses**: Fake refraction by sampling the background starfield with distorted UVs based on the lens normals, mixed with a bright rim light (Fresnel) and chromatic aberration.
- **Energy Tethers**: Emissive shading with an animated glowing pulse (`sin(time + length)`).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Celestial Astrolabe
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// Parameters mapped to u.zoom_params
// u.zoom_params.x: Astrolabe Complexity
// u.zoom_params.y: Rotation Speed
// u.zoom_params.z: Lens Refraction Index
// u.zoom_params.w: Tether Energy Pulse

struct Uniforms {
    // ... matching renderer layout
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    // ...
}

// SDFs
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 { ... }
fn sdLens(p: vec3<f32>, radius: f32, thickness: f32) -> f32 { ... }

// Helpers
fn rot(a: f32) -> mat2x2<f32> { ... }

// Map function
fn map(p: vec3<f32>) -> vec2<f32> {
    // 1. Mouse distortion logic
    // 2. Nested rotating rings using sdTorus
    // 3. Central and outer lenses using sdLens
    // 4. Energy tethers
    // Return distance and material ID
}

// Background Starfield
fn getStarfield(dir: vec3<f32>) -> vec3<f32> { ... }

// Main Compute
@compute @workgroup_size(8, 8, 1)
fn main(...) {
    // 1. Ray setup and mouse interaction (orbit/gravity)
    // 2. Raymarching the astrolabe
    // 3. If hit glass material: calculate refraction vector, march further or sample getStarfield()
    // 4. Shading: Brass metallic BRDF approximation, energy tether emission, Fresnel for glass
    // 5. Output to writeTexture
}
```

## Parameters (for UI sliders)
Name (default, min, max, step)
- Astrolabe Complexity (1.0, 0.5, 3.0, 0.1)
- Rotation Speed (0.5, 0.0, 2.0, 0.05)
- Lens Refraction (1.2, 1.0, 2.0, 0.01)
- Tether Energy (0.8, 0.0, 2.0, 0.1)

## Integration Steps
- Create shader file `public/shaders/gen-celestial-astrolabe.wgsl`
- Create JSON definition `shader_definitions/generative/gen-celestial-astrolabe.json`
- Run `generate_shader_lists.js`
- Upload via `storage_manager`
