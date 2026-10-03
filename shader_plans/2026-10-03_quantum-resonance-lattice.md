# New Shader Plan: Quantum Resonance Lattice

## Overview
A highly ordered lattice of vibrating quantum nodes that spontaneously shatters and reconstitutes in rhythmic waves, creating a mesmerizing tension between crystalline rigidity and fluid mechanics.

## Features
- Infinite domain repetition of octohedral quantum nodes
- Harmonic wave functions perturbing the lattice structure
- Physically based rendering with chromatic dispersion
- Interactive spatial gravity well that tears the lattice apart
- Bioluminescent energy filaments connecting nearest neighbors
- Dynamic sub-surface scattering on node surfaces

## Technical Implementation
- File: public/shaders/gen-quantum-resonance-lattice.wgsl
- Category: generative
- Tags: ["quantum", "lattice", "raymarching", "SDF", "chromatic-aberration"]
- Algorithm: A raymarching renderer utilizing a folded spatial domain with a grid of SDF octahedrons distorted by multi-frequency sinusoidal waves and simplex noise.

### Core Algorithm
The spatial domain is divided into a continuous 3D grid using modulo arithmetic (`q = p - round(p/c)*c`). Each cell contains an octahedron SDF. The position of each cell is fed into a multi-frequency 3D noise function and sinusoidal wave system (based on `u.config.x`) to calculate local displacement and rotation. As time progresses, waves of entropy sweep through the lattice, causing local regions to dissolve into chaotic particle-like noise before re-aligning.

### Mouse Interaction
When `u.zoom_config.w > 0.0`, the mouse cursor (mapped from `u.zoom_config.yz`) acts as a miniature black hole. A gravitational distortion field is applied to the raymarching coordinates, stretching and tearing the lattice towards the cursor's world-space equivalent.

### Color Mapping / Shading
Nodes are rendered with a metallic base. Illumination is calculated using a primary directional light and a vibrant ambient term derived from the cell's 3D index. Chromatic dispersion is approximated by rendering slightly offset color channels based on the ray's travel distance and distance from the mouse well.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Quantum Resonance Lattice
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
  config: vec4<f32>,              // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,         // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,         // .xyzw = user params p1..p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

// --- CORE LOGIC ---

// Helper for 3D rotation
fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    // ... rotation matrix generation ...
    return mat3x3<f32>();
}

// SDF for Octahedron
fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let p_abs = abs(p);
    return (p_abs.x + p_abs.y + p_abs.z - s) * 0.57735027;
}

// Map function returning distance and material id
fn map(p: vec3<f32>) -> vec2<f32> {
    // Domain repetition
    let spacing = u.zoom_params.x * 2.0 + 1.0;
    let cell = floor(p / spacing + 0.5);
    var q = p - cell * spacing;

    // Wave disruption
    let t = u.config.x;
    let wave = sin(cell.x * 0.5 + t) * cos(cell.z * 0.5 + t) * u.zoom_params.y;
    q += vec3<f32>(0.0, wave, 0.0);

    // Mouse distortion
    if (u.zoom_config.w > 0.0) {
        // ... apply gravity well ...
    }

    let d = sdOctahedron(q, 0.5);
    return vec2<f32>(d, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let coord = vec2<i32>(gid.xy);
    if (coord.x >= i32(res.x) || coord.y >= i32(res.y)) { return; }

    let uv = (vec2<f32>(coord) - 0.5 * res) / res.y;

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, u.config.x * u.zoom_params.z);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching loop
    var t = 0.0;
    var d = 0.0;
    var steps = 0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res2 = map(p);
        d = res2.x;
        if (d < 0.001 || t > 50.0) { break; }
        t += d;
        steps++;
    }

    // Coloring
    var col = vec3<f32>(0.0);
    if (t < 50.0) {
        let ao = 1.0 - f32(steps) / 100.0;
        col = vec3<f32>(0.2, 0.5, 1.0) * ao;
    }

    // Output
    textureStore(writeTexture, coord, vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, coord, vec4<f32>(t, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(0.0));
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Node Spacing (1.5, 0.5, 3.0, 0.1)
- Wave Amplitude (1.0, 0.0, 3.0, 0.1)
- Travel Speed (2.0, 0.0, 5.0, 0.1)
- Chaos Factor (0.5, 0.0, 1.0, 0.05)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
