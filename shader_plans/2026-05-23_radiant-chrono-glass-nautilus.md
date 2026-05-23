# New Shader Plan: Radiant Chrono-Glass Nautilus

## Overview
A hyper-organic, infinitely spiraling nautilus shell forged from refractive chrono-glass and glowing liquid-plasma, dynamically unfolding its geometric chambers and pulsating with cosmic energy in perfect synchronization with ambient sonic frequencies.

## Features
- Infinitely spiraling logarithmic fractal geometry forming a cosmic nautilus shell.
- Refractive chrono-glass rendering with chromatic aberration and internal liquid-plasma scattering.
- Bioluminescent energy pulses traveling along the shell's ridges driven by audio frequencies.
- Dynamic unfolding and folding of chambers based on low-frequency acoustic impacts.
- Mouse-interactive gravity well that distorts the local space-time fabric around the nautilus.

## Technical Implementation
- File: public/shaders/gen-radiant-chrono-glass-nautilus.wgsl
- Category: generative
- Tags: ["fractal", "nautilus", "chrono-glass", "plasma", "audio-reactive", "organic"]
- Algorithm: Logarithmic fractal domain repetition combined with smooth min SDFs and raymarched volumetric scattering for the internal plasma.

### Core Algorithm
Raymarching a complex logarithmic spiral SDF with domain folding along the spiral axis. The shell material utilizes a refractive index simulation combined with chromatic aberration. The interior contains a volumetric plasma field generated using 3D simplex noise advected by audio-reactive time vectors, combined using smooth-min functions to create organic, fleshy connections between the glass chambers.

### Mouse Interaction
Mouse position is mapped to a 3D gravity well in the raymarching domain. The space-time distortion applies a localized swirling displacement function `p' = p * rotate3D(mouse_dist * 0.5)`, pulling the nautilus fractal into a black-hole-like vortex.

### Color Mapping / Shading
The exterior glass uses an iridescent chromatic mapping (cyan/magenta/gold) driven by viewing angle (Fresnel) and normal curvature. The internal plasma utilizes a dense subsurface scattering approximation, glowing with intense bioluminescent cyan and deep violet, blooming intensely at the center of the spiral.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Radiant Chrono-Glass Nautilus
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

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Shatter Threshold, y=Chime Density, z=Refraction Index, w=Transmission
    ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // 1. Core raymarching loop for logarithmic nautilus SDF
    // 2. Volumetric subsurface scattering for the plasma core
    // 3. Audio-reactive unfolding driven by u.config.z
    // 4. Iridescent chromatic coloring logic
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- "Spiral Tightness" (0.5, 0.1, 1.0, 0.01)
- "Plasma Bloom" (1.5, 0.0, 5.0, 0.1)
- "Glass Refraction" (1.33, 1.0, 2.5, 0.01)
- "Audio Reactivity" (0.8, 0.0, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "[YYYY-MM-DD]_[slug].md" "[Catchy Title]"
Reply with only: "✅ Plan created and queued: [YYYY-MM-DD]_[slug].md"
