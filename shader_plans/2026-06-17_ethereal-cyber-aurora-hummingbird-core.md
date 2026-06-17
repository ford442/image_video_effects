# New Shader Plan: Ethereal Cyber-Aurora Hummingbird-Core

## Overview
A hyper-fast, biomechanical hummingbird woven from liquid auroral plasma and shattered quantum glass, hovering within a massive chrono-distortion flower.

## Features
- A hyper-detailed central avian figure formed from shifting refractive plasma.
- Rapidly fluttering wings composed of overlapping fractal light-trails that react to high-frequency audio.
- A central "chrono-flower" gravity well that pulses and distorts the space around the bird.
- Luminous particle "pollen" drifting in the volumetric void, reacting to ambient bass.
- A shimmering, cyber-organic skeletal structure visible beneath the plasma.
- High-intensity chromatic aberration scaling with the "Speed" parameter.

## Technical Implementation
- File: public/shaders/gen-ethereal-cyber-aurora-hummingbird-core.wgsl
- Category: generative
- Tags: ["organic", "biomechanical", "aurora", "plasma", "quantum"]
- Algorithm: A combination of high-frequency temporal domain warping for the wings, smooth-min SDFs for the cyber-organic body, and volumetric raymarching for the auroral plasma trails.

### Core Algorithm
- **SDFs:** The body is constructed using a series of elongated ellipsoid SDFs blended with `smin`, warped by low-frequency noise. The wings are flat, thin boxes heavily displaced by a high-frequency sine wave based on time and local space.
- **Noise Type:** 3D Value noise for volumetric pollen, and simplex noise for the auroral plasma texture mapped onto the body SDF.
- **Domain Repetition:** Radial repetition is used for the petals of the surrounding chrono-flower gravity well.

### Mouse Interaction
- The mouse position controls the rotation of the entire scene and shifts the focal point of the chrono-flower gravity well, creating a localized spatial distortion (lens effect) around the cursor.

### Color Mapping / Shading
- Colors are driven by a dynamic palette mixing deep cyan, magenta, and intense neon yellow. The wings use a refractive transmission model, while the body emits an auroral bloom.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Ethereal Cyber-Aurora Hummingbird-Core
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Flutter Speed, y=Aura Intensity, z=Pollen Density, w=Aberration
    ripples: array<vec4<f32>, 50>,
};

// ... Raymarching setup, SDFs, lighting and coloring ...

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // Basic setup...
}
```

Parameters (for UI sliders)

Flutter Speed (1.0, 0.1, 5.0, 0.1) -> zoom_params.x
Aura Intensity (0.5, 0.0, 2.0, 0.05) -> zoom_params.y
Pollen Density (1.0, 0.0, 3.0, 0.1) -> zoom_params.z
Aberration (0.2, 0.0, 1.0, 0.01) -> zoom_params.w

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
