# New Shader Plan: Luminous-Fluid Chladni-Resonator

## Overview
A mesmerizing, bioluminescent liquid surface that physically organizes itself into hyper-complex, evolving Chladni resonant figures driven by low-frequency audio interference patterns, blending fluid dynamics with precise acoustic geometry.

## Features
- **Acoustic Geometry Spawning**: Standing wave patterns dynamically form intricate, multi-layered Chladni plates.
- **Bioluminescent Fluidity**: The resonant nodes are filled with a glowing, neon-liquid substance that behaves like a non-Newtonian fluid.
- **Harmonic Interference Generation**: Intersecting sine waves and multi-octave noise create evolving, interference-based geometric structures.
- **Surface Tension Mapping**: Audio frequencies modulate fluid viscosity, causing sharp, crystalline nodes or smooth, rippling anti-nodes.
- **Quantum Chromatic Dispersion**: Colors shift dynamically across the visible spectrum based on resonance amplitude, driven by the `plasmaBuffer`.

## Technical Implementation
- File: public/shaders/gen-luminous-fluid-chladni-resonator.wgsl
- Category: generative
- Tags: ["chladni", "cymatics", "fluid", "resonance", "audio-reactive", "bioluminescent"]
- Algorithm: Evaluates multiple 2D standing waves with time-varying frequencies, combining their amplitudes to create resonance nodes. A secondary fluid-simulation pass (using fractional Brownian motion) advects the nodes, causing them to pool and string together like liquid metal or neon plasma.

### Core Algorithm
The core evaluates a generalized Chladni plate equation: `Z(x,y) = A * sin(n*pi*x)*sin(m*pi*y) + B * sin(m*pi*x)*sin(n*pi*y)`. `n` and `m` smoothly interpolate based on `u.config.x` (time) and audio input, creating shifting resonance modes. A noise field (fBm) perturbs the spatial coordinates to simulate fluid advection.

### Mouse Interaction
The mouse acts as an acoustic dampener. The distance from the mouse `u.config.zw` attenuates the resonance amplitude, causing the fluid structure to dissolve into a chaotic, unorganized state in a circular radius around the cursor.

### Color Mapping / Shading
Resonance nodes (where amplitude ~ 0) gather the highest concentration of glowing fluid, mapped to sharp neon greens/blues using a steep gradient. Anti-nodes map to deep, dark voids. Chromatic dispersion is added along the gradients of the scalar field.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Luminous-Fluid Chladni-Resonator
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// Standing wave function
fn chladni(uv: vec2<f32>, n: f32, m: f32, t: f32) -> f32 {
    let pi = 3.14159265;
    let term1 = sin(n * pi * uv.x) * sin(m * pi * uv.y);
    let term2 = sin(m * pi * uv.x) * sin(n * pi * uv.y);
    return cos(t) * term1 + sin(t) * term2;
}

// Pseudo-random and noise
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// fBm for fluid distortion
fn fbm(p: vec2<f32>) -> f32 {
    // ... typical fbm implementation
    return 0.0; // placeholder
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // 1. Setup coordinates & resolution
    // 2. Calculate time and dynamic resonance modes (n, m)
    // 3. Apply fluid distortion (fBm) to UVs
    // 4. Calculate Chladni resonance field
    // 5. Apply mouse dampening interaction
    // 6. Map field intensity to glowing neon colors
    // 7. Write to writeTexture
}
```

## Parameters (for UI sliders)
Name (default, min, max, step)
- Mode N (3.0, 1.0, 10.0, 0.1)
- Mode M (5.0, 1.0, 10.0, 0.1)
- Fluidity (0.5, 0.0, 1.0, 0.05)
- Glow Intensity (1.5, 0.1, 5.0, 0.1)
