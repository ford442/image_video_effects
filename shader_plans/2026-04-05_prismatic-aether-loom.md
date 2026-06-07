# New Shader Plan: Prismatic Aether-Loom

## Overview
A hyper-dimensional weaving machine where threads of liquid light are spun into iridescent fabrics of space-time, dynamically reacting to audio frequencies and cosmic winds.

## Features
- Infinite expanse of glowing, interwoven light threads that dynamically braid themselves.
- Chromatic dispersion creating thin-film interference patterns across the woven fabric.
- Audio-reactive loom mechanisms that pulse and shift the fabric's tension (`u.config.y`).
- Parallax-driven cosmic winds that displace the threads using domain-warped FBM.
- Kinetic hyper-cylinders that act as the loom's mechanical framework, rotating in 4D space.

## Technical Implementation
- File: public/shaders/gen-prismatic-aether-loom.wgsl
- Category: generative
- Tags: ["cosmic", "mechanical", "strings", "iridescent", "audio-reactive"]
- Algorithm: Raymarching infinite cylindrical lattices with domain warping and KIFS interference.

### Core Algorithm
Utilizes a raymarching engine to render infinite intersecting cylinders representing the threads. A KIFS fold applies the intricate "braiding" mechanism, while domain-warped FBM noise introduces the cosmic wind displacement. The density and complexity of the threads are driven by `u.zoom_params`.

### Mouse Interaction
The mouse acts as a localized gravity sheer, twisting the thread lattice into a vortex around the cursor. The distortion uses a smooth step decay based on the distance from `u.zoom_config.y` and `u.zoom_config.z`, simulating a black hole tearing through the loom.

### Color Mapping / Shading
Iridescent thin-film shading using a cosine-based color palette to simulate chromatic dispersion along the threads. Ambient occlusion and soft shadows emphasize the depth of the woven layers, with bioluminescent bloom mapping to the audio amplitude (`u.config.y`).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Prismatic Aether-Loom
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Thread Density, y=Braid Complexity, z=Cosmic Wind, w=Chromatic Shift
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// Custom mod function
fn mod_f32(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

// ... SDFs, Raymarching, and Shading functions go here ...

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let coords = vec2<i32>(id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(coords) / res;

    // Main execution ...
    let color = vec4<f32>(uv, 0.5, 1.0);
    textureStore(writeTexture, coords, color);
}
```

## Parameters (for UI sliders)

Name (default, min, max, step)
- Thread Density (10.0, 1.0, 50.0, 1.0)
- Braid Complexity (3.0, 1.0, 10.0, 1.0)
- Cosmic Wind (0.5, 0.0, 2.0, 0.1)
- Chromatic Shift (1.0, 0.0, 5.0, 0.1)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
