# New Shader Plan: Sentient Aether-Plasma Nebula-Moth

## Overview
A hyper-organic, bioluminescent space-moth woven from liquid auroral plasma and shattered chrono-glass, fluttering endlessly through a chaotic, violently decaying quantum-particle storm.

## Features
- Intricate, fractal-based volumetric wings that ripple with bioluminescent temporal shockwaves.
- Dynamic, particle-storm void background driven by deep acoustic resonance.
- Bioluminescent antennae that emit shifting chromatic light into the surrounding aether.
- Chaotic quantum-fluid distortions simulating the tearing of a time-rift as the wings beat.
- A glowing liquid-aurora thorax that pulsates intensely in sync with heavy sub-bass frequencies.
- Crystalline, shattered chrono-glass dust trailing from the wings.

## Technical Implementation
- File: public/shaders/gen-sentient-aether-plasma-nebula-moth.wgsl
- Category: generative
- Tags: ["organic", "quantum", "cosmic", "volumetric", "fractal"]
- Algorithm: Raymarching a complex SDF of a moth structure combined with domain distortion for chaotic quantum storms and fbm for aether-plasma wings.

### Core Algorithm
The moth's core SDF is constructed from capped cones and ellipsoids with heavy smooth-min operations. The wings use domain-warped fractal brownian motion (fBM) to simulate glowing liquid plasma, perturbed by temporal sinusoidal noise. The background particle storm uses Voronoi noise mapped to a volumetric accumulation loop.

### Mouse Interaction
The mouse coordinates (`u.zoom_config.y` and `u.zoom_config.z`) are mapped to an orbital camera rotation, allowing the viewer to pan around the fluttering moth while shifting the gravity well of the quantum storm.

### Color Mapping / Shading
Uses a shifting palette of auroral greens, quantum purples, and bioluminescent cyan. The shading integrates fake subsurface scattering for the moth's thorax, metallic reflections for the chrono-glass fragments, and heavy bloom/glow for the plasma wings.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Sentient Aether-Plasma Nebula-Moth
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

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```

## Parameters (for UI sliders)
- `u.zoom_params.x`: Wing Flutter Frequency (default 1.0, 0.1, 5.0, 0.1)
- `u.zoom_params.y`: Quantum Storm Intensity (default 0.5, 0.0, 2.0, 0.05)
- `u.zoom_params.z`: Aether-Plasma Glow (default 0.8, 0.0, 3.0, 0.1)
- `u.zoom_params.w`: Time Rift Distortion (default 0.2, 0.0, 1.0, 0.01)
