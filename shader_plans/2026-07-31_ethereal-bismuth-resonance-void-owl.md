# New Shader Plan: Ethereal Bismuth-Resonance Void-Owl

## Overview
A hyper-dimensional avian entity forged from iridescent bismuth lattices, suspended in a zero-gravity quantum field where sonic vibrations materialize as glowing geometric feathers. The aesthetic blends crystalline art-deco structures with surreal cyber-mysticism, radiating an aurora-like spectrum of neon cyan, magenta, and gold.

## Features
- Iridescent bismuth step-growth geometry forming the owl's skeletal structure.
- Audio-reactive quantum feathers that bloom and shatter based on bass frequencies.
- Slowly morphing iridescent refraction and subsurface scattering on the crystal facets.
- Gravitational lens distortions around the core singularity (the heart/eyes).
- Dynamic orbital debris fields of floating glowing monoliths.
- Slowly breathing volumetric aurora fog representing the void-ether.

## Technical Implementation
- File: public/shaders/gen-ethereal-bismuth-resonance-void-owl.wgsl
- Category: generative
- Tags: ["crystal", "bismuth", "avian", "iridescent", "void", "quantum"]
- Algorithm: Raymarching combined with multi-octave domain folding and audio-reactive SDF displacements.

### Core Algorithm
The central SDF uses a combination of folded spaces (`abs()` and `mod()`) and box-framing to create step-like bismuth crystal structures forming an abstract owl shape. We apply audio reactivity (`plasmaBuffer[0].x`) to the scaling and displacement of the feathers (secondary intersecting capsules/planes). A 3D noise texture is sampled for the background volumetric fog.

### Mouse Interaction
The mouse cursor (`u.zoom_config.yz`) acts as a localized quantum singularity, pulling the surrounding orbital debris (floating monoliths) into a swirling vortex and distorting the nearby crystal lattices through a spatial twist function.

### Color Mapping / Shading
A custom iridescence function uses the dot product of the surface normal and the view vector, modulated by time, to cycle through intense neon gradients (cyan, magenta, yellow, gold). We add artificial subsurface scattering by accumulating color samples along the ray path and implement a strong post-process bloom for the neon highlights.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Ethereal Bismuth-Resonance Void-Owl
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var<storage, read> plasmaBuffer: array<vec4<f32>>;
@group(0) @binding(5) var<storage, read> touchBuffer: array<vec4<f32>>;
@group(0) @binding(6) var<storage, read> layer_1: array<vec4<f32>>;
@group(0) @binding(7) var<storage, read> layer_2: array<vec4<f32>>;
@group(0) @binding(8) var<storage, read> layer_3: array<vec4<f32>>;
@group(0) @binding(9) var depthTexture: texture_depth_2d;
@group(0) @binding(10) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(11) var non_filtering_sampler: sampler;
@group(0) @binding(12) var<storage, read> extraBuffer: array<vec4<f32>>;

struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    frame: u32,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    view_matrix: mat4x4<f32>,
    proj_matrix: mat4x4<f32>,
    camera_pos: vec3<f32>,
    config: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// ... Setup raymarching framework, rotation matrices, iridescence palette, and SDFs for the bismuth structures.

fn sdf(p: vec3<f32>) -> f32 {
    // Domain folding for bismuth crystal structures
    // Incorporating audio reactivity from plasmaBuffer[0].x
    // Morphing based on zoom_params.x and zoom_params.y
    return 1.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) GlobalInvocationID: vec3<u32>) {
    let uv = vec2<f32>(GlobalInvocationID.xy) / u.resolution;
    // ... Raymarching loop, normal calculation, shading with iridescence, subsurface scattering, bloom, and textureStore to writeTexture.
    textureStore(writeTexture, vec2<i32>(GlobalInvocationID.xy), vec4<f32>(uv, 0.5, 1.0));
}
```

## Parameters (for UI sliders)
- `zoom_params.x`: Crystal Complexity (Fold Iterations) (default: 0.5, min: 0.0, max: 1.0, step: 0.01)
- `zoom_params.y`: Audio Reactivity Scale (default: 0.5, min: 0.0, max: 1.0, step: 0.01)
- `zoom_params.z`: Iridescence Shift (Color Cycling) (default: 0.5, min: 0.0, max: 1.0, step: 0.01)
- `zoom_params.w`: Orbital Debris Density (default: 0.5, min: 0.0, max: 1.0, step: 0.01)
