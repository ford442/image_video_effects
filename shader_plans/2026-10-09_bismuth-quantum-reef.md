# New Shader Plan: Bismuth Quantum Reef

## Overview
A mesmerizing, infinite landscape of shifting iridescent geometric crystals that evolve like a digital, extraterrestrial coral reef.

## Features
- Infinite raymarched domain repetition of geometric, crystalline structures (SDFs).
- Dynamic, iridescent color mapping that shifts based on view angle and normal vector (Bismuth-like effect).
- Quantum fluctuation distortions applied to the geometry using multi-octave 3D noise.
- Subsurface scattering approximations for a glowing, semi-translucent crystal aesthetic.
- Audio reactive pulses (if audio data available) or time-based rhythmic expanding waves.
- Interactive gravity well effect driven by mouse position.

## Technical Implementation
- File: public/shaders/gen-bismuth-quantum-reef.wgsl
- Category: generative
- Tags: ["3d", "raymarching", "fractal", "crystal", "iridescent", "bismuth"]
- Algorithm: Raymarching through a domain-repeated SDF field combining boxes and octahedrons, displaced by simplex noise, with iridescent shading based on Fresnel and normal mapping.

### Core Algorithm
The core is a raymarcher. The space is repeated using `fract(p)` or `mod(p)` techniques. The primary SDF is a boolean intersection or smooth minimum of an octahedron and a box to create complex crystal shapes. Multi-octave 3D noise (e.g., value noise or simplex) displaces the surface slightly to give it a grown, organic imperfection. A secondary slowly morphing displacement creates the "quantum fluctuation".

### Mouse Interaction
When the mouse is clicked (`u.zoom_config.w > 0.0`), the `mouse_uv` (`u.zoom_config.yz`) acts as a localized gravity well. Rays passing near the corresponding 3D world coordinate are bent towards it, and the SDF structures in that radius are smoothed out or scaled up, creating a interactive ripple/distortion effect.

### Color Mapping / Shading
Shading is primarily driven by the surface normal and the view direction. A Fresnel term calculates the base iridescence, mapped through a cosine-based color palette (like Inigo Quilez's palettes) to produce the vibrant pinks, blues, and golds characteristic of bismuth crystals. Fake subsurface scattering is achieved by sampling the SDF slightly deeper inside the object and adding a soft glow based on a secondary color palette (e.g., cyan/teal).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Bismuth Quantum Reef
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// Constants & Utilities
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

// Pseudo-random and noise functions...
// SDF primitives (box, octahedron, smooth union)...

// Map function (Domain repetition + SDF evaluation)
fn map(p: vec3<f32>) -> f32 {
    // Domain repetition
    // Mouse distortion
    // Base crystal SDF
    // Noise displacement
    return d;
}

// Raymarching loop
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> f32 {
    // standard raymarch loop
    return d;
}

// Calculate normal
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    // standard gradient calculation
    return n;
}

// Iridescent Color Palette
fn palette(t: f32) -> vec3<f32> {
    // Cosine based palette for Bismuth colors
    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }
    let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
    let uv = (fragCoord - 0.5 * resolution) / resolution.y;

    // Camera setup
    // Raymarching
    // Shading (Iridescence, Fake SSS, Fresnel)
    // Post-processing (bloom, vignette)

    let finalColor = vec4<f32>(col, 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Quantum Fluctuation (0.5, 0.0, 1.0, 0.01)
- Crystal Density (1.0, 0.5, 2.0, 0.1)
- Iridescence Shift (0.0, 0.0, 1.0, 0.01)
- SSS Glow (0.3, 0.0, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
