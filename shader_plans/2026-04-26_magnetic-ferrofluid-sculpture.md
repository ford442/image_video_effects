# New Shader Plan: Magnetic Ferrofluid-Sculpture

## Overview
A hyper-reflective, organic-mechanical mass of magnetic liquid that constantly shifts and forms razor-sharp crystalline spikes, rippling fluid dynamics, and metallic peaks driven by audio frequencies.

## Features
- Dynamic ferrofluid spikes that grow, snap, and dissolve based on sonic bass input.
- Hyper-reflective, liquid-metal chrome material with multi-chromatic iridescent highlights.
- Viscous organic fluid dynamics blended with sharp, rigid magnetic field lines using smooth-min (smin).
- Audio-reactive gravitational distortions that twist and warp the liquid mass into complex topologies.
- Raymarched volumetric shadows and ambient occlusion to enhance the metallic texture.
- Mouse interaction that acts as a localized magnetic polar attractor, pulling spikes toward the cursor.

## Technical Implementation
- File: public/shaders/gen-magnetic-ferrofluid-sculpture.wgsl
- Category: generative
- Tags: ["ferrofluid", "magnetic", "liquid-metal", "organic", "audio-reactive"]
- Algorithm: Raymarching through a dynamically distorted domain, using 3D value noise and smooth-minimum blending of spheres and cones to simulate spiking ferrofluid.

### Core Algorithm
- Primary geometry is a central blob composed of a base sphere blended with many extruded spiky shapes.
- Use 3D Perlin/simplex noise driven by time and audio to distort the surface normals and create liquid ripples.
- Spikes are generated using domain repetition or procedural instancing around the sphere, with their heights modulated by the audio envelope (`u.config.y`).
- Smooth-minimum (`smin`) is extensively used to seamlessly melt the sharp spikes into the spherical fluid body.

### Mouse Interaction
- The mouse acts as a localized magnetic pole (`u.mouse`).
- Raymarching distance function calculates the vector to the mouse position and gently deforms the SDF towards the mouse, generating a secondary fluid bulge or pulling the nearest spikes toward the user.

### Color Mapping / Shading
- Base color is a deep, highly reflective liquid silver/chrome.
- Iridescence (rainbow sheen) mapped to surface curvature and viewing angle (Fresnel effect).
- Intense specular highlights and deep ambient occlusion in the valleys between spikes.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Magnetic Ferrofluid-Sculpture
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    resolution: vec2<f32>,
    mouse: vec2<f32>,
    time: f32,
    frame: u32,
    config: vec4<f32>, // x: unused, y: audio, z: unused, w: unused
    zoom_params: vec4<f32>, // mapped to UI sliders
};

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// ... Additional raymarching and sdf functions

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.resolution.x) || global_id.y >= u32(u.resolution.y)) { return; }
    // Render loop
}
```

Parameters (for UI sliders)

- Spike Density (0.5, 0.1, 1.0, 0.01)
- Fluid Viscosity (0.3, 0.0, 1.0, 0.01)
- Iridescence (0.7, 0.0, 1.0, 0.01)
- Magnetic Pull (0.5, 0.0, 1.0, 0.01)

Integration Steps

- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
