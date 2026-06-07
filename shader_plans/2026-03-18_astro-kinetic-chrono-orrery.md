# New Shader Plan: Astro-Kinetic Chrono-Orrery

## Overview
A hyper-intricate cosmic mechanism of nested, rotating brass and energy rings orbiting a blazing quantum singularity, merging celestial mechanics with clockwork precision.

## Features
- Nested, rotating metallic rings representing temporal gears
- Quantum dust trapped in the gravity wells between gears
- Time-dilation effects warping space and color near the center
- Audio-reactive gear synchronization and energy pulses
- Subsurface scattering on the outer crystal casing
- Mouse-controlled 3D rotation of the entire mechanism

## Technical Implementation
- File: public/shaders/gen-astro-kinetic-chrono-orrery.wgsl
- Category: generative
- Tags: ["cosmic", "mechanical", "clockwork", "quantum", "orrery"]
- Algorithm: Raymarching with nested rotational transformations and domain repetition, creating a complex, animated mechanical structure that orbits a central singularity.

### Core Algorithm
Raymarching an SDF scene comprising tori and cylinders rotated around different axes. Time is multiplied by fractional offsets to create a continuous gear-like motion. Space is folded using `mod` and polar coordinates. The central singularity uses intense fBM noise to simulate a blazing quantum star.

### Mouse Interaction
Mouse coordinates act as an external gravity mass. The `u.pointer` X and Y coordinates map to the pitch and yaw of the entire orrery structure, allowing the user to rotate the complex mechanism in 3D space. Clicking adds energy to `u.config.y`, spinning the gears faster and increasing the central star's brightness.

### Color Mapping / Shading
The metallic gears use a physically based shading model approximation (diffuse and specular terms) tinted with bronze, gold, and oxidized copper palettes. The central star uses an HDR bloom effect mapping a spectrum from deep ultraviolet to blinding white based on the density of the noise field.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Astro-Kinetic Chrono-Orrery
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// --- GLOBALS & STRUCTS ---
const MAX_STEPS = 100;
const SURF_DIST = 0.001;
const MAX_DIST = 100.0;

// --- MATH & SDF HELPERS ---
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(vec2<f32>(p.x, p.z)) - t.x, p.y);
    return length(q) - t.y;
}

// --- MAIN MAPPING ---
fn map(p: vec3<f32>) -> f32 {
    var d = MAX_DIST;
    var q = p;
    // Apply mouse rotation
    let rot_yz = rot2D(u.pointer.y * 3.14) * vec2<f32>(q.y, q.z);
    q.y = rot_yz.x;
    q.z = rot_yz.y;

    let rot_xz = rot2D(u.pointer.x * 3.14) * vec2<f32>(q.x, q.z);
    q.x = rot_xz.x;
    q.z = rot_xz.y;

    // Add rings
    for(var i = 0; i < 4; i++) {
        let fi = f32(i);

        let rot_xy = rot2D(u.time * 0.2 * (fi + 1.0) + u.config.y) * vec2<f32>(q.x, q.y);
        q.x = rot_xy.x;
        q.y = rot_xy.y;

        let rot_yz_inner = rot2D(0.5) * vec2<f32>(q.y, q.z);
        q.y = rot_yz_inner.x;
        q.z = rot_yz_inner.y;

        let ring = sdTorus(q, vec2<f32>(2.0 + fi * 0.5, 0.05));
        d = min(d, ring);
    }
    return d;
}

// --- COMPUTE MAIN ---
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    let uv = (vec2<f32>(id.xy) * 2.0 - dims) / dims.y;

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    for(var i=0; i<MAX_STEPS; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if(d < SURF_DIST || t > MAX_DIST) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    if(t < MAX_DIST) {
        // Base coloring
        col = vec3<f32>(0.8, 0.6, 0.2) * (1.0 - t/MAX_DIST);
    }

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)

Complexity (4.0, 1.0, 10.0, 1.0)
Speed (1.0, 0.0, 5.0, 0.1)
Glow Intensity (1.0, 0.0, 3.0, 0.1)
Audio Reactivity (0.5, 0.0, 1.0, 0.05)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
