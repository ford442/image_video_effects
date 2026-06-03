# New Shader Plan: Kryonic Quantum-Aether Fractal-Core

## Overview
A pulsating, zero-gravity containment field where hyper-frozen fractal geometries endlessly unfold and shatter into luminous aether-plasma shards, reacting aggressively to ambient sonic impulses.

## Features
- Intricate KIFS (Kaleidoscopic Iterated Function System) fractals that simulate frozen, crystalline structures.
- Audio-reactive shattering, where high-frequency sounds cause the fractal edges to break into glowing plasma particles.
- Volumetric aether-fog rendering using raymarching with subsurface scattering.
- Mouse-interactive thermal injection, melting the frozen core into chaotic liquid-plasma.
- Chromatic aberration and crystalline light refraction at the edges of the fractal geometry.
- Hypnotic, slow-breathing rhythmic expansion of the central core.

## Technical Implementation
- File: public/shaders/gen-kryonic-quantum-aether-fractal-core.wgsl
- Category: generative
- Tags: ["fractal", "quantum", "reactive", "raymarching", "crystalline"]
- Algorithm: Raymarching with distance estimation for KIFS fractals, combined with a particle dispersion field for shattered fragments.

### Core Algorithm
The base geometry is generated via a 3D KIFS fractal folded along multiple symmetry axes, with iteration count linked to audio intensity. SDF (Signed Distance Field) is evaluated iteratively. When audio spikes, the distance field is offset by a high-frequency Voronoi noise to simulate cracking, and a secondary particle layer is spawned from the gradient of the SDF.

### Mouse Interaction
The mouse acts as a localized thermal heat source (a gravity/heat well). As the mouse moves closer to the fractal geometry, it subtracts from the SDF, causing a localized "melt" effect which interpolates the rigid fractal folds into a smooth, liquid-plasma metaball noise field.

### Color Mapping / Shading
The coloring uses a cryogenic palette (deep cyan, glacial blue, void black) mapping depth to color, with subsurface scattering on the thinner crystal edges. The shattered plasma particles glow with intense electric blue and magenta emission, combined with fake volumetric blooming on the final pass.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Kryonic Quantum-Aether Fractal-Core
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
    zoom_params: vec4<f32>,  // x=Fractal Scale, y=Shatter Intensity, z=Glow Strength, w=Thermal Melt
    ripples: array<vec4<f32>, 50>,
};

// Math and Hash Functions
const PI: f32 = 3.14159265359;

// KIFS Fractal folding function
fn fold(p: vec3<f32>) -> vec3<f32> {
    var p_mut = p;
    p_mut = abs(p_mut);
    if (p_mut.x < p_mut.y) { p_mut = p_mut.yxz; }
    if (p_mut.x < p_mut.z) { p_mut = p_mut.zyx; }
    if (p_mut.y < p_mut.z) { p_mut = p_mut.xzy; }
    return p_mut;
}

// Distance Estimation
fn map(p: vec3<f32>) -> f32 {
    return length(p) - 1.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<i32>(i32(id.x), i32(id.y));

    var color = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    textureStore(writeTexture, coords, color);
}
```

Parameters (for UI sliders)

Fractal Scale (1.5, 0.5, 5.0, 0.1)
Shatter Intensity (0.5, 0.0, 2.0, 0.01)
Glow Strength (1.0, 0.1, 3.0, 0.1)
Thermal Melt (0.2, 0.0, 1.0, 0.05)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
