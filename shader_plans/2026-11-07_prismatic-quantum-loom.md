# New Shader Plan: Prismatic Quantum Loom

## Overview
A hyper-dimensional weaving of chromatic threads that respond to cosmic gravity, creating an ethereal, glowing lattice of pure light and quantum entanglement.

## Features
- Intricate, intertwined volumetric energy threads
- Dynamic multi-spectral chromatic dispersion
- Responsive gravitational distortions based on mouse position
- Smooth, continuous domain-warped noise patterns
- Deep, high-contrast glow with subsurface light scattering effects

## Technical Implementation
- File: public/shaders/gen-prismatic-quantum-loom.wgsl
- Category: generative
- Tags: ["cosmic", "quantum", "neon", "geometry", "lattice"]
- Algorithm: Raymarching a domain-warped volumetric grid of SDF cylinders with chromatic accumulation.

### Core Algorithm
Raymarch through an infinite lattice created by repeating space (modulo). Apply 3D Simplex noise to the domain space before evaluating the SDF of intersecting cylinders. The distance field represents energy threads. Light accumulation calculates depth and chromatic shift to simulate multi-spectral light paths.

### Mouse Interaction
The mouse cursor acts as a quantum singularity. It creates a localized gravity well that bends the ray direction and stretches the domain space radially towards `u.zoom_config.yz`, scaling the distortion strength with distance and input state (`u.zoom_config.w`).

### Color Mapping / Shading
Color is accumulated iteratively along the ray using a density function. Density is mapped to a gradient shifting through deep indigo, bright cyan, neon pink, and gold. A bloom effect is approximated by accumulating a soft minimum distance per step.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Prismatic Quantum Loom
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

// Core parameters mapped from UI
// u.zoom_params.x = Thread Density
// u.zoom_params.y = Chromatic Shift
// u.zoom_params.z = Gravity Well Strength
// u.zoom_params.w = Quantum Fluctuation Speed

// Math constants and helpers
const PI: f32 = 3.14159265359;

// Domain repetition
fn opRep(p: vec3<f32>, c: vec3<f32>) -> vec3<f32> {
    return (p + 0.5 * c) % c - 0.5 * c;
}

// 2D Rotation
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Map function
fn map(pos: vec3<f32>) -> f32 {
    let time = u.config.x * u.zoom_params.w;
    var p = pos;

    // Apply domain warping based on time
    p.x += sin(p.z * 0.5 + time) * 0.2;
    p.y += cos(p.x * 0.5 + time * 0.8) * 0.2;

    // Domain repetition
    let spacing = vec3<f32>(1.5 / u.zoom_params.x);
    p = opRep(p, spacing);

    // SDF of intersecting threads
    let threadRadius = 0.05;
    let d1 = length(p.xy) - threadRadius;
    let d2 = length(p.yz) - threadRadius;
    let d3 = length(p.zx) - threadRadius;

    return min(min(d1, d2), d3);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<f32>(f32(global_id.x), f32(global_id.y));

    if (coord.x >= resolution.x || coord.y >= resolution.y) {
        return;
    }

    // Normalized device coordinates (-1 to 1)
    let uv = (coord - 0.5 * resolution) / resolution.y;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -3.0 + u.config.x * 0.5);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse Gravity Interaction
    if (u.zoom_config.w > 0.5) {
        let mousePos = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(resolution.x/resolution.y, 1.0);
        let distToMouse = length(uv - mousePos);
        let pull = exp(-distToMouse * 3.0) * u.zoom_params.z;
        rd.xy += (mousePos - uv) * pull;
        rd = normalize(rd);
    }

    // Raymarching loop
    var t = 0.0;
    var color = vec3<f32>(0.0);
    var glow = 0.0;

    for (var i = 0; i < 64; i++) {
        let p = ro + rd * t;
        let d = map(p);

        if (d < 0.001 || t > 10.0) {
            break;
        }

        t += d;
        // Accumulate chromatic glow
        glow += 0.02 / (0.01 + d * d);
    }

    // Chromatic shifting based on depth and params
    let shift = u.zoom_params.y;
    color += vec3<f32>(
        sin(t * 1.0 + shift) * 0.5 + 0.5,
        sin(t * 1.2 + shift + 2.0) * 0.5 + 0.5,
        sin(t * 1.4 + shift + 4.0) * 0.5 + 0.5
    ) * glow * 0.05;

    // Tonemapping
    color = color / (1.0 + color);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
}
```

## Parameters (for UI sliders)
- `thread_density`: default 1.0, min 0.5, max 3.0, step 0.1
- `chromatic_shift`: default 0.0, min 0.0, max 6.28, step 0.1
- `gravity_well_strength`: default 0.5, min 0.0, max 2.0, step 0.05
- `quantum_fluctuation_speed`: default 1.0, min 0.1, max 5.0, step 0.1

## Integration Steps
- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
