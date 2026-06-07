# New Shader Plan: Chromatic Singularity-Loom

## Overview
A majestic, gravity-warped cosmic loom weaving fractal strings of pure light around a central singularity, endlessly pulling geometric constellations into the event horizon.

## Features
- **Central Event Horizon**: A swirling, ultra-dense singularity that severely distorts the light and geometry passing near it.
- **Fractal Light-Threads**: Iridescent, multi-layered geometric strings that continuously weave and tangle in an orbital dance.
- **Gravitational Lensing**: Extreme spacetime curvature bends the background threads into mesmerizing, looping mirages around the core.
- **Audio-Reactive Accretion Disk**: High frequencies trigger volatile bursts of plasma and energy rings radiating from the singularity.
- **Mouse Event Control**: The mouse cursor perturbs the delicate balance of the loom, tearing the strings or dragging the singularity's core.

## Technical Implementation
- File: public/shaders/gen-chromatic-singularity-loom.wgsl
- Category: generative
- Tags: ["singularity", "fractal", "weaving", "space", "audio-reactive", "distortion"]
- Algorithm: Raymarching a complex, folding space where SDFs (representing threads and energy rings) are heavily distorted by a gravitational lens formula `p = p + (normalize(p) * mass) / length(p)`. The light threads are generated using a combination of domain repetition and recursive fractal folding (KIFS).

### Core Algorithm
- **Singularity Lens**: Apply a nonlinear spatial warp `p = p + p * (gravity_mass / dot(p, p))` to bend raymarching space before evaluating objects.
- **KIFS Light Strings**: Use Kaleidoscopic Iterated Function Systems to generate the endlessly recursive threads of the loom, shifting rotation angles based on time and distance from the center.
- **Accretion Plasma**: A volumetric raymarching pass using 3D Perlin noise that evaluates density and color based on audio spectrum layers.

### Mouse Interaction
- The mouse position dynamically offsets the singularity center, pulling the entire scene's geometry towards the cursor.

### Color Mapping / Shading
- The threads use a phase-shifted cosine palette for extreme chromatic aberration and iridescence. The accretion disk samples `plasmaBuffer` based on the noise density, multiplied by an intense exponential bloom factor.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Chromatic Singularity-Loom
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // included as per plan

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>
};

// --- CONSTANTS & HELPERS ---
const MAX_STEPS: i32 = 120;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.005;

// Rotate 2D vector
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Map function evaluating the singularity and fractal threads
fn map(p: vec3<f32>, time: f32, audio_intensity: f32) -> vec2<f32> {
    var pos = p;

    // Gravitational Lensing effect
    let center = vec3<f32>(0.0);
    let dist_sq = dot(pos - center, pos - center);
    let mass = 2.0;
    if (dist_sq > 0.0) {
        pos += normalize(pos) * (mass / dist_sq);
    }

    // KIFS Fractal for threads
    for (var i = 0; i < 4; i++) {
        pos = abs(pos) - vec3<f32>(0.5 + audio_intensity * 0.2);
        let r = rot(time * 0.2 + f32(i));
        let x_new = r[0][0]*pos.x + r[0][1]*pos.y;
        let y_new = r[1][0]*pos.x + r[1][1]*pos.y;
        pos.x = x_new;
        pos.y = y_new;
    }

    // Thread SDF
    let d1 = length(pos.xz) - 0.05;

    // Singularity Core SDF
    let d2 = length(p - center) - 1.0;

    return vec2<f32>(min(d1, d2), 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // 1) Initialize UVs and Camera
    // 2) Raymarch the gravity-warped environment
    // 3) Calculate phase-shifted chromatic colors
    // 4) Render audio-reactive accretion disk
    // 5) Write out final color
}
```

## Parameters (for UI sliders)

Name (default, min, max, step)
- Gravity Mass (2.0, 0.1, 10.0, 0.1)
- Thread Density (4.0, 1.0, 8.0, 1.0)
- Accretion Glow (1.0, 0.0, 5.0, 0.1)
- Chromatic Shift (0.5, 0.0, 1.0, 0.01)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
