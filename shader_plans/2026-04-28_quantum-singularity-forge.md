# New Shader Plan: Quantum Singularity-Forge

## Overview
A colossal, gravity-warped cosmic forge where swirling ribbons of superheated stardust and hyper-dense dark matter collide, violently forging and ejecting glowing geometric constellations that pulsate and spin in sync with rhythmic audio frequencies.

## Features
- Infinite, twisting accretion disk of glowing, volumetric plasma clouds.
- Hyper-dense central singularity that severely warps the surrounding light via simulated gravitational lensing.
- Rhythmic ejection of crystalline, wireframe-like geometric constellations driven by heavy bass frequencies.
- High-contrast color palette of deep void blacks, searing stellar whites, and iridescent accretion glows.
- Swirling starfield background mapped onto a warped domain space.

## Technical Implementation
- File: public/shaders/gen-quantum-singularity-forge.wgsl
- Category: generative
- Tags: ["cosmic", "quantum", "gravity", "fractal", "audio-reactive"]
- Algorithm: Raymarching with domain warping and smooth volumetric accumulation

### Core Algorithm
Raymarching scene where the primary object is a distorted torus (the accretion disk) and a black hole (sphere with a negative refraction index for lensing). Rhythmic geometry generation using KIFS (Kaleidoscopic Iterated Function Systems) for the ejected constellations. The density and glow of the plasma are mapped via layered 3D value noise.

### Mouse Interaction
Mouse movement dynamically shifts the camera around the singularity, simulating an orbital view while slightly modulating the gravitational lensing strength to warp the background heavily at the edges of the cursor.

### Color Mapping / Shading
Deep space colors derived from a heat-map gradient (black -> dark indigo -> vibrant cyan -> searing white core) for the plasma, with the crystalline constellations emitting pure iridescent chromatic dispersion based on viewing angle.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Quantum Singularity-Forge
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>
};

// ... (full skeleton with comments)
```

## Parameters (for UI sliders)
- Singularity Gravity: `u.zoom_params.x` (0.1, 0.01, 1.0, 0.01)
- Accretion Speed: `u.zoom_params.y` (0.5, 0.1, 2.0, 0.05)
- Ejection Rate: `u.zoom_params.z` (0.3, 0.0, 1.0, 0.01)

## Integration Steps
- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
