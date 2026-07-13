# New Shader Plan: Abyssal Quantum-Crystal Void-Manta

## Overview
A colossal, majestic cyber-manta ray gliding silently through an abyssal quantum-fluid sea, its wings forged from shimmering crystalline fractals that scatter chromatic auroral light and ripple dynamically with cosmic bass frequencies.

## Features
- **Fractal Crystal Wings:** Procedural wing structures built using recursive domain folding and crystalline SDFs.
- **Quantum Fluid Sea:** Volumetric raymarching of a dense, swirling abyssal environment with bioluminescent particulate matter.
- **Audio-Reactive Pulses:** Wing beats and bioluminescent vein patterns that surge and glow in direct synchronization with acoustic low-end frequencies.
- **Chromatic Dispersion:** Deep iridescent shading on the manta's body that mimics the scattering of light through shattered quantum glass.
- **Fluid Temporal Distortion:** A trail of cascading chrono-fractals that warp the spatial coordinates of the surrounding void fluid.

## Technical Implementation
- File: public/shaders/gen-abyssal-quantum-crystal-void-manta.wgsl
- Category: generative
- Tags: ["organic", "quantum", "cosmic", "manta", "crystal", "audio-reactive"]
- Algorithm: Raymarching complex geometric SDFs combined with volumetric noise accumulation for the void fluid.

### Core Algorithm
The manta ray's core shape is constructed using bounded extruded shapes and smooth min/max operations to blend a sleek, streamlined cyber-body. The wings use iterative fractal folding (`p.xy = abs(p.xy) - offset;`) layered with rotation matrices. The void sea employs a volumetric rendering technique, accumulating density from 3D fractional Brownian motion (fBm) noise over the raymarching steps, tinted with abyssal blues and bioluminescent cyans.

### Mouse Interaction
The mouse uniform (`u.mouse`) drives a localized gravitational wave that ripples through the quantum fluid. Specifically, the distance from the mouse pointer to the ray origin deflects the raymarching direction slightly, creating a lens-like distortion effect around the cursor, simulating a dense gravity well dragging the manta and the void fluid.

### Color Mapping / Shading
The manta utilizes a subsurface scattering approximation by sampling the SDF thickness and applying a spectral gradient map based on normal dot view directions (Fresnel). The quantum fluid blends from deep abyssal indigo to vibrant cyan and magenta at high acoustic amplitudes. Emission is driven heavily by the structural crevasses on the manta's back.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Abyssal Quantum-Crystal Void-Manta
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    resolution: vec4<f32>,
    mouse: vec4<f32>,
    time: vec4<f32>,
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    ripples: vec4<f32>,
    slider1: f32,
    slider2: f32,
    slider3: f32,
    slider4: f32,
    slider5: f32,
    slider6: f32,
    slider7: f32,
    slider8: f32,
}

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

// --- Math & Noise Helpers ---
const PI = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ... (full skeleton with comments)
```

## Parameters (for UI sliders)

Name (default, min, max, step)
- `slider1` (Wing Fractal Detail): (3.0, 1.0, 5.0, 1.0)
- `slider2` (Fluid Density): (0.5, 0.0, 1.0, 0.01)
- `slider3` (Audio Reactivity): (1.0, 0.0, 2.0, 0.1)
- `slider4` (Bioluminescence Glow): (0.8, 0.0, 1.0, 0.05)
- `slider5` (Manta Speed): (1.0, 0.1, 3.0, 0.1)

## Integration Steps

- Create shader file `public/shaders/gen-abyssal-quantum-crystal-void-manta.wgsl`
- Create JSON definition `shader_definitions/generative/gen-abyssal-quantum-crystal-void-manta.json`
- Run `node scripts/generate_shader_lists.js`
- Upload via storage manager `python scripts/sync_shaders_to_storage.py`
- Complete pre-commit steps to ensure proper testing, verification, review, and reflection are done.
