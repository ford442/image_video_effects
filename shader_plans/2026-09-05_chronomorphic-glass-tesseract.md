# New Shader Plan: Chronomorphic Glass Tesseract

## Overview
A hyper-dimensional glass structure that continuously folds through time and space, refracting shifting iridescent cosmic energies.

## Features
- **4D Tesseract Rotation:** Seamlessly rotating hypercube projected into 3D space, creating intricate, non-euclidean geometry.
- **Raymarched Dispersion:** Physically inspired chromatic dispersion through transparent glass surfaces.
- **Chronomorphic Distortion:** Space and geometry organically ripple and warp based on temporal sine waves.
- **Iridescent Internal Reflections:** Internal bouncing light creating shifting pearlescent spectrums based on viewing angle.
- **Dynamic Gravity Lenses:** Mouse interaction acts as a localized gravity well, severely bending the glass structure and background light.
- **Volumetric Caustics:** Ethereal light projections emitting from the core of the tesseract into the surrounding void.

## Technical Implementation
- File: public/shaders/gen-chronomorphic-glass-tesseract.wgsl
- Category: generative
- Tags: ["3d", "raymarching", "glass", "tesseract", "iridescent", "refraction"]
- Algorithm: Raymarching an SDF of a projected 4D hypercube, using multiple ray bounces for refraction and internal reflections, coupled with chromatic aberration and spatial domain distortion.

### Core Algorithm
The SDF is built using a projected 4D hypercube. A base 4D point `(x, y, z, w)` is rotated in multiple 4D planes (e.g., XW, YW, ZW) using rotation matrices driven by time. This is projected down to 3D. The resulting geometry uses a bounding box or specialized hypercube SDF formula, which is further modified by a subtle, low-frequency 3D noise field to create "chronomorphic" ripples in the structure's surface.

### Mouse Interaction
The mouse (`zoom_config.yz`) dictates the center of a strong spatial distortion field. Rays approaching this coordinate are bent severely towards or away from it (acting as a gravitational lens or repulsive force). The intensity is modulated by `zoom_params.w` (Gravity Strength) and mouse click state.

### Color Mapping / Shading
Shading relies heavily on refraction. The ray hits the surface, calculates the normal (using a small epsilon offset SDF sampling), and refracts based on an IOR parameter. Instead of a single ray, the fragment uses three offset IORs (Red, Green, Blue) to create chromatic dispersion. Internal structures (smaller embedded tesseracts) are shaded with a pearlescent iridescence formula based on the view vector and surface normal dot product (Fresnel). The background is a soft, deep cosmic gradient (dark violet to absolute black).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Chronomorphic Glass Tesseract
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
  zoom_params: vec4<f32>,  // .x = Fold Speed, .y = Dispersion, .z = Refraction IOR, .w = Gravity
  ripples: array<vec4<f32>, 50>,
};

// ... constants (PI, TAU) and helper functions (rot, hash, sdf)

// SDF for 4D Tesseract projection
fn sdf_tesseract(p: vec3<f32>) -> f32 {
    // 4D projection and folding logic
    // ...
    return 0.0;
}

// Raymarching loop with refraction
fn march(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    // ...
    return vec3<f32>(0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // coordinate setup, camera, ray direction, shading, and textureStore
    // ...
}
```

Parameters (for UI sliders)

Fold Speed (1.0, 0.0, 3.0, 0.1)
Dispersion (0.05, 0.0, 0.2, 0.01)
Refraction IOR (1.33, 1.0, 2.5, 0.05)
Gravity (0.5, 0.0, 1.0, 0.01)
