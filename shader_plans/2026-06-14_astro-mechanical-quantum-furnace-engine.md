# New Shader Plan: Astro-Mechanical Quantum-Furnace Engine

## Overview
A towering, slowly rotating cosmic engine composed of interlocking brass-like fractal gears floating in a deep-space nebula, powered by an intensely glowing core of quantum particle systems that spew audio-reactive aether plasma.

## Features
- Intricate volumetric KIFS fractals generating hyper-detailed, interlocking mechanical gears.
- A swirling, liquid-plasma quantum-furnace core that erupts with bioluminescent light in sync with acoustic frequencies.
- Multi-layered cosmic void background filled with slow-drifting, iridescent auroral dust.
- Audio-reactive particle exhaust streams where bass frequencies (`u.config.y`) drive the expansion and ejection velocity of quantum plasma.
- High-refraction metallic shading mimicking oxidized cosmic brass and luminescent liquid-chrome.
- Dynamic magnetic distortion fields that gently warp the mechanical structures based on an evolving time variable (`u.config.x`).
- Cinematic depth of field blurring the distant mechanical layers of the cosmic loom.

## Technical Implementation
- File: public/shaders/gen-astro-mechanical-quantum-furnace-engine.wgsl
- Category: generative
- Tags: ["mechanical", "quantum", "cosmic", "particle systems", "audio-reactive"]
- Algorithm: Volumetric SDF raymarching combined with domain repetition and KIFS fractals. The core combines deformed intersecting spheres with multi-octave fBm to simulate the quantum plasma furnace.

### Core Algorithm
The central mechanical structure is generated using a combination of toroidal SDFs and KIFS (Kaleidoscopic Iterated Function Systems) to create infinitely detailed gear teeth. A central spherical cavity houses the quantum core, where 3D Simplex noise and fractional Brownian motion (fBm) drive a volumetric raymarching pass that outputs dense, glowing plasma emissions. Particles are simulated via domain-warped voronoi noise injected into the emission calculations.

### Mouse Interaction
The mouse (`u.zoom_config.y`, `u.zoom_config.z`) dictates an artificial gravity well. As the cursor moves, the outer fractal gears realign their rotational axis toward the cursor, while the emitted quantum plasma streams are violently pulled into the distortion field, bending the visual light around the interaction point.

### Color Mapping / Shading
The mechanical components use a physically-based approach (simulated) with a high metallic value, relying on an environment mapping distortion for reflections. The plasma core maps audio frequencies to a fiery, high-energy gradient shifting from deep cyan to intense blinding white-gold. Subsurface scattering is faked using distance-based glow accumulations within the volumetric stepping loop.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Astro-Mechanical Quantum-Furnace Engine
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```
Parameters (for UI sliders)

Name (default, min, max, step)
- Gear Complexity (0.5, 0.0, 1.0, 0.01)
- Plasma Intensity (0.8, 0.0, 2.0, 0.01)
- Refraction Index (1.3, 1.0, 2.5, 0.01)
- Emission Threshold (0.4, 0.0, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
