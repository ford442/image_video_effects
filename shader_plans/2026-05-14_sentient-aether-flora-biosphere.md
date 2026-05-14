# New Shader Plan: Sentient Aether-Flora Biosphere

## Overview
A hyper-organic, bioluminescent extraterrestrial terrarium where fractal aether-spores drift and blossom into complex, sentient crystalline flora that pulse with cosmic energy in sync with ambient audio.

## Features
- Procedurally generated 3D fractal branching (L-systems via SDFs) for the aether-flora
- Bioluminescent subsurface scattering effect on the translucent flora petals
- Volumetric aether-spore particle system floating within the terrarium
- Audio-reactive blooming and color-shifting of the flowers
- Interactive gravity well: mouse movement influences spore flow and gently sways the flora

## Technical Implementation
- File: public/shaders/gen-sentient-aether-flora-biosphere.wgsl
- Category: generative
- Tags: ["flora", "organic", "bioluminescent", "fractal", "audio-reactive"]
- Algorithm: Volumetric raymarching of procedurally twisted and repeated SDF cylinders (branches) and folded SDF planes (petals), combined with a domain-wrapped particle system for the spores.

### Core Algorithm
Utilizes raymarching with Domain Repetition (`opRep`) to create a forest of flora. The flora stems are created using smooth-blended `sdCylinder` primitives, twisted along the Y-axis using `opTwist`. The petals are folded using absolute value functions (KIFS-like folding) on `sdPlane` combined with `sdSphere` intersections. The scene is enveloped in a subtle 3D noise field for volumetric aether-fog.

### Mouse Interaction
The `u.mouse` coordinates create a 3D gravity well in the domain. Spore positions are smoothly attracted towards the mouse vector using an inverse-square distance falloff. The global twist parameter for the flora stems is also slightly offset based on horizontal mouse movement to simulate a physical breeze.

### Color Mapping / Shading
The shading model employs a custom subsurface scattering approximation by sampling the SDF slightly along the view vector behind the hit point. The surface uses a vivid iridescent gradient mapping (`mix(base_color, neon_pink, fresnel)`), dynamically shifted by the low-frequency audio spectrum data from `u.custom_data`. The aether-spores use additive blending for a glowing bloom effect.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Sentient Aether-Flora Biosphere
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// --- Helper Functions ---
// 3D Noise, SDF Primitives (sdCylinder, sdSphere), opTwist, opRep

// --- Raymarching ---
// map(pos): returns vec2 (distance, material_id)
// calcNormal(pos): returns vec3 normal

// --- Main Compute Shader ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // 1. Setup UVs and Ray (Camera)
    // 2. Raymarch loop
    // 3. Shading & Subsurface Scattering approximation
    // 4. Volumetric Spore accumulation (secondary raymarch step or analytic intersection)
    // 5. Audio-reactive color shifting and Mouse Interaction
    // 6. Output to writeTexture
}
```

## Parameters (for UI sliders)

- Bloom Intensity (1.5, 0.0, 5.0, 0.1)
- Flora Density (2.0, 0.5, 5.0, 0.1)
- Spore Count (100.0, 10.0, 500.0, 10.0)
- Audio Reactivity (1.0, 0.0, 2.0, 0.1)

## Integration Steps

1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
