# New Shader Plan: Chronos Crystal Labyrinth

## Overview
A mind-bending journey through an infinite, self-folding tesseract of crystalline structures where time distortion ripples visualize as chromatic refraction patterns. This shader creates a sensation of navigating a multidimensional clockwork maze built of light, bridging organic growth algorithms with rigid geometric precision.

## Features
- Infinite folding space utilizing domain repetition and recursive modulo operations.
- Volumetric raymarching through refractive SDF crystals.
- Chromatic aberration and heavy dispersion mimicking dense optical mediums.
- Temporal distortion waves driven by audio-reactive low-frequency data.
- Interactive gravity wells via mouse input that bends the local crystal structures.
- Soft subsurface scattering for glowing, ethereal internal reflections.
- Evolving metallic and dielectric material properties based on fractal noise.

## Technical Implementation
- File: public/shaders/gen-chronos-crystal-labyrinth.wgsl
- Category: generative
- Tags: ["crystal", "tesseract", "fractal", "refraction", "raymarching", "time-distortion"]
- Algorithm: Volumetric raymarching of a folded SDF space with refractive light bouncing and multi-layered chromatic dispersion.

### Core Algorithm
The environment is built using a base octahedral SDF combined with Menger sponge-like recursive hollowing. The coordinate space is folded using `abs(p) - s` multiple times to create intricate repeating corridors. A 4D noise function (Simplex or Perlin extended) offsets the SDF distances to create an organic, growing feel over the rigid geometry. Volumetric light is accumulated by stepping through the SDF and calculating transmittance and phase scattering.

### Mouse Interaction
The mouse acts as a localized mass singularity. When the mouse moves or is clicked, a gravity well is formed, bending the ray directions (`rd`) around the pointer coordinate. The distortion formula uses an inverse square law (`distortion = u.zoom_params.y / (1.0 + pow(length(uv - u.zoom_config.yz), 2.0))`) to warp the space seamlessly.

### Color Mapping / Shading
The shading utilizes a custom PBR-like approach for transparent media. Instead of standard diffuse/specular, it computes ray refraction indices based on three distinct wavelengths (RGB). It samples normal maps derived from the SDF gradient and computes fresnel reflectance. The core glows with a subsurface scattering approximation using blurred distance samples, creating a rich palette of deep violets, crystalline blues, and sharp gold refractions.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Chronos Crystal Labyrinth
// Category: generative
// ----------------------------------------------------------------
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
  zoom_params: vec4<f32>,  // .x = Dispersion, .y = Gravity Strength, .z = Fractal Fold, .w = Glow Intensity
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// Distance functions
fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let q = abs(p);
    return (q.x + q.y + q.z - s) * 0.57735027;
}

// Map the world
fn map(p: vec3<f32>) -> f32 {
    var q = p;

    // Domain repetition / folding
    q = abs(q) - u.zoom_params.z;
    q = abs(q) - u.zoom_params.z * 0.5;

    // Core geometry
    let d = sdOctahedron(q, 1.0);

    // Add noise displacement
    // (Noise logic here)
    return d;
}

// Raymarching loop
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);
    if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) {
        return;
    }

    let resolution = vec2<f32>(f32(dims.x), f32(dims.y));
    var uv = vec2<f32>(coords) / resolution;
    uv = uv * 2.0 - 1.0;
    uv.x *= resolution.x / resolution.y;

    // Setup camera and rays
    let ro = vec3<f32>(0.0, 0.0, -5.0 + u.config.x);
    let ta = vec3<f32>(0.0, 0.0, 0.0);

    // Raymarching, lighting, and refraction logic goes here

    // Write out final pixel
    let col = vec4<f32>(uv, 0.5, 1.0); // Placeholder
    textureStore(writeTexture, coords, col);
}
```

## Parameters (for UI sliders)
- Dispersion (default 1.2, min 0.5, max 3.0, step 0.1)
- Gravity Strength (default 0.5, min 0.0, max 2.0, step 0.05)
- Fractal Fold (default 2.0, min 1.0, max 5.0, step 0.1)
- Glow Intensity (default 1.0, min 0.0, max 3.0, step 0.1)
