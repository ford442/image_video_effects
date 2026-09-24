# New Shader Plan: Aetherial Cyber-Phoenix Feather-Lattice

## Overview
A hyper-stylized digital rebirth simulating intricate bio-mechanical feather structures igniting in a quantum thermal bath of neon fire.

## Features
- Volumetric glowing plasma trails forming overlapping cyber-feathers
- Intricate SDF-based fractal barbs weaving into a macro-lattice
- Thermogenic color mapping from deep ash-blues to blinding hyper-orange and magenta
- Interactive cursor-driven gravity well that bends the feather lattice and ignites the tips
- Generative organic movement simulating slow cosmic respiration
- Iridescent metallic subsurface scattering on the primary structural shafts

## Technical Implementation
- File: public/shaders/gen-aetherial-cyber-phoenix-feather-lattice.wgsl
- Category: generative
- Tags: ["phoenix", "cyber", "feathers", "plasma", "fractal", "interactive"]
- Algorithm: Raymarching through domain-repeated SDFs for structural feathers, intertwined with multi-octave simplex noise for the volumetric plasma fire.

### Core Algorithm
The space is partitioned using a hexagonal domain repetition scheme to form a tessellated lattice. Within each cell, an elongated capsule SDF represents the primary shaft. Secondary, thinner structures (barbs) branch off by modulating the local coordinates with a high-frequency sine wave and bounded domain repetition. Multi-octave 3D Simplex noise perturbs the SDF distances to create an organic, frayed edge characteristic of feathers catching fire.

### Mouse Interaction
The cursor introduces a localized spherical distortion in the domain. The distance to the mouse cursor acts as an exponential attractor (gravity well) pulling the fractal feathers inward, while simultaneously injecting a massive heat spike to the color formula, turning the affected area bright, blinding white-hot plasma.

### Color Mapping / Shading
Color is driven by a custom heat-map gradient based on the accumulated density and distance to the SDF core. The base shafts are shaded with a metallic iridescence (using dot products of normals and ray direction). The edges transition through deep obsidian, saturated magenta, fiery orange, and intense neon yellow. The bloom is accumulated over ray steps.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Aetherial Cyber-Phoenix Feather-Lattice
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
    zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
    zoom_params: vec4<f32>,  // .x = Fire Intensity, .y = Audio React, .z = Lattice Density, .w = Iridescence
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 90;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 50.0;

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Map function calculating the SDF of the feather lattice
fn map(p: vec3<f32>) -> vec2<f32> {
    // Spatial domain repetition and noise perturbation for feathers
    var pos = p;
    // ... custom map logic
    return vec2<f32>(length(pos) - 1.0, 1.0); // Dummy return
}

// Raymarching loop
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var dO: f32 = 0.0;
    var mat: f32 = 0.0;
    for(var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let d = map(p);
        dO += d.x;
        mat = d.y;
        if(d.x < SURF_DIST || dO > MAX_DIST) { break; }
    }
    return vec2<f32>(dO, mat);
}

// Compute Normals
fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dim = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(id.xy) - 0.5 * dim) / dim.y;
    let time = u.config.x;

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    let rm = raymarch(ro, rd);
    let d = rm.x;

    var col = vec3<f32>(0.0);

    if(d < MAX_DIST) {
        let p = ro + rd * d;
        let n = getNormal(p);
        let heat = u.zoom_params.x; // mapped from Uniforms

        // Lighting & Coloring
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);

        col = vec3<f32>(diff) * vec3<f32>(1.0, 0.4, 0.1) * heat;
    }

    // Output
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)

Fire Intensity (1.0, 0.0, 2.0, 0.01)
Audio React (0.5, 0.0, 1.0, 0.01)
Lattice Density (1.0, 0.5, 3.0, 0.1)
Iridescence (0.8, 0.0, 1.0, 0.01)
