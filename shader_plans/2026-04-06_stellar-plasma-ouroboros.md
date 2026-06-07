# New Shader Plan: Stellar Plasma-Ouroboros

## Overview
An infinite, self-consuming mechanical serpent made of fractured glass scales and stellar plasma, merging cosmic, mechanical, and particle systems.

## Features
- Infinite raymarched mechanical serpent body looping through cosmic space.
- Fractured, refractive glass scales that scatter light and distort background stars.
- Roaring internal core of stellar plasma that reacts to audio frequencies.
- Gravity-warped accretion disk of shattered particles orbiting the serpent.
- Mouse interaction creates gravitational anomalies that twist and bend the serpent's path.

## Technical Implementation
- File: public/shaders/gen-stellar-plasma-ouroboros.wgsl
- Category: generative
- Tags: ["cosmic", "mechanical", "plasma", "refractive", "audio-reactive"]
- Algorithm: Raymarching with domain repetition, KIFS folding, volumetric FBM plasma, and chromatic dispersion.

### Core Algorithm
- **Geometry:** Raymarching an infinite cylinder (the serpent) heavily distorted by sine waves and KIFS folds to create the segmented, scaly armor.
- **Scales:** Boolean intersections of the cylinder with repeating hexagonal patterns to carve out the glass scales.
- **Plasma Core:** Inside the cylinder, volumetric raymarching samples 3D FBM noise to create a boiling, glowing stellar core. Audio input (`u.config.y`) drives the boiling volatility and emission intensity.

### Mouse Interaction
- The mouse (`u.zoom_config.yz`) acts as a gravitational anomaly. As the raymarched coordinates approach the anomaly, a localized twist deformation is applied to space, causing the serpent to spiral toward the cursor.

### Color Mapping / Shading
- **Scales:** Highly specular, utilizing chromatic dispersion (slight color channel offsets in the reflection/refraction vectors) to simulate fractured glass.
- **Plasma:** Blackbody radiation gradient, mapping density to vibrant oranges, purples, and blinding whites.
- **Ambient:** Deep cosmic void with sparse, twinkling star-field background.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Stellar Plasma-Ouroboros
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Scale Density, y=Plasma Intensity, z=Anomaly Gravity, w=Time Warp
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// ... SDFs, FBM, Raymarching Loop, Main Compute ...

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // Implement raymarching and rendering here
}
```

## UI Parameters
Parameters (for UI sliders)

- Scale Density (10.0, 1.0, 50.0, 1.0) -> mapped to `u.zoom_params.x`
- Plasma Intensity (2.0, 0.1, 10.0, 0.1) -> mapped to `u.zoom_params.y`
- Anomaly Gravity (0.5, 0.0, 2.0, 0.05) -> mapped to `u.zoom_params.z`
- Time Warp (1.0, 0.1, 5.0, 0.1) -> mapped to `u.zoom_params.w`

## Integration Steps
1. Create shader file `public/shaders/gen-stellar-plasma-ouroboros.wgsl`
2. Create JSON definition `shader_definitions/generative/gen-stellar-plasma-ouroboros.json`
3. Run `node scripts/generate_shader_lists.js`
4. Upload via `storage_manager`
