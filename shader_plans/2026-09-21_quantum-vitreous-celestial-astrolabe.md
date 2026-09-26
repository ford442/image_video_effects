# New Shader Plan: Quantum-Vitreous Celestial-Astrolabe

## Overview
A mesmerizing descent into a multi-dimensional cosmic timepiece where interlocking, iridescent glass rings rotate independently, projecting golden holographic constellations that distort light through quantum refraction.

## Features
- **Nested SDF Rings:** Multiple independently rotating torus/cylinder SDFs forming a complex gyroscopic structure.
- **Glass Refraction:** Raymarching with index of refraction (IOR) approximations to simulate thick, warped glass.
- **Chromatic Aberration:** RGB channels split during the refraction calculation for a rainbow rim-lighting effect.
- **Holographic Runes:** A layer of emissive golden symbols embedded within the inner rings, mapped via domain repetition and noise.
- **Dynamic Depth of Field:** Focus distance linked to time and mouse, blurring distant rings to enhance the miniature scale.
- **Quantum Bloom:** Intense, bleeding light from the inner core that saturates the surrounding glass.

## Technical Implementation
- File: public/shaders/gen-quantum-vitreous-celestial-astrolabe.wgsl
- Category: generative
- Tags: ["raymarching", "glass", "hologram", "sdf", "cosmic", "astrolabe"]
- Algorithm: Advanced raymarching with multi-pass dielectric shading, temporal rotation matrices, and additive emissive blending.

### Core Algorithm
- **SDFs:** The core consists of 4-5 concentric torus SDFs (`sdTorus`) and thin cylindrical bands (`sdCylinder`).
- **Domain Manipulation:** Each ring applies a different 3D rotation matrix (e.g., `mat3` derived from Euler angles modulated by `u.time`).
- **Raymarching Loop:** The primary raymarches to the glass boundary. A secondary "internal" raymarches through the volume to calculate absorption and hit the inner emissive core.

### Mouse Interaction
- **Orbital Camera:** Mouse X and Y directly control the spherical coordinates (azimuth and elevation) of the camera orbiting the astrolabe.
- **Focal Shift:** Mouse click/drag alters the index of refraction (`ior`) and core bloom intensity, making the astrolabe appear to power up.

### Color Mapping / Shading
- **Base Material:** Dark, translucent obsidian glass with specular highlights (`pow(max(dot(N, H), 0.0), 64.0)`).
- **Emissive Core:** Glowing gold/amber (`vec3(1.0, 0.7, 0.2)`) fading into deep quantum blue (`vec3(0.1, 0.3, 1.0)`) at the edges.
- **Post-Processing:** Chromatic aberration by offset sampling the final accumulated color, plus a vignette and soft bloom.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Quantum-Vitreous Celestial-Astrolabe
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    mouse: vec4<f32>,
    zoom_params: vec4<f32>,
    speed_params: vec4<f32>,
    color_params: vec4<f32>,
    extra_params: vec4<f32>,
}

// Custom rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// SDF Torus
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// Map function for the scene
fn map(p: vec3<f32>) -> vec2<f32> {
    var res = vec2<f32>(999.0, -1.0);
    // ... Ring logic with rotation matrices
    return res;
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    // ... EPS based normal
    return vec3<f32>(0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let tex_coords = vec2<i32>(id.xy);
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (tex_coords.x >= dims.x || tex_coords.y >= dims.y) { return; }

    // UV setup
    let uv = (vec2<f32>(tex_coords) - 0.5 * vec2<f32>(dims)) / f32(dims.y);

    // Camera setup with mouse interaction
    // Raymarching loop (primary and refraction)
    // Shading and composition

    let final_color = vec4<f32>(uv, 0.5, 1.0); // Placeholder
    textureStore(writeTexture, tex_coords, final_color);
}
```
Parameters (for UI sliders)

- zoom_params.x: Zoom Level (1.0, 0.1, 5.0, 0.1)
- speed_params.x: Rotation Speed (1.0, 0.0, 3.0, 0.05)
- color_params.x: Core Hue (0.1, 0.0, 1.0, 0.01)
- extra_params.x: IOR (Index of Refraction) (1.45, 1.0, 3.0, 0.01)