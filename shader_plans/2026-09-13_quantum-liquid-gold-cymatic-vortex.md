# New Shader Plan: Quantum Liquid-Gold Cymatic-Vortex

## Overview
A hyper-fluid, liquid gold vortex reacting to sound and magnetic forces, where acoustic resonance sculpts geometric cymatic patterns into the shifting metallic surface.

## Features
- Fluid dynamics simulation via layered curl noise and radial domain distortion.
- Hyper-realistic liquid gold metallic shading with simulated environmental reflections.
- Audio-reactive cymatic patterns that ripple outwards from the central vortex core.
- Magnetic mouse interaction that bends the vortex flow and alters the surface tension.
- Quantum interference moiré patterns at the event horizon of the central singularity.
- Smooth fractional Brownian motion (fBm) integration for the surrounding liquid ocean.

## Technical Implementation
- File: public/shaders/gen-quantum-liquid-gold-cymatic-vortex.wgsl
- Category: generative
- Tags: ["liquid", "gold", "vortex", "cymatic", "audio-reactive", "metallic"]
- Algorithm: Raymarching an infinite plane distorted by time-varying sinusoidal fields and nested 3D curl noise, applying dynamic SDF deformations driven by audio buffer inputs.

### Core Algorithm
The shader will use raymarching onto a distorted base plane (SDF). The plane's height and normal will be perturbed by a multi-octave fBm mixed with 3D curl noise. A strong radial twist will be applied to the domain based on the distance from the center, creating the vortex effect. High-frequency cymatic patterns will be overlaid using concentric sine waves modulated by angular frequency (polar coordinates).

### Mouse Interaction
The mouse will act as a magnetic attractor. It will warp the domain around its UV coordinates, causing the liquid flow to curve towards or away from the cursor. The distance to the mouse will also locally decrease the "viscosity" (noise scale), creating smoother, more mirror-like metallic pools.

### Color Mapping / Shading
The surface will use a custom PBR-style metallic shading approximation. Base color will be a rich, warm gold. Lighting will be calculated using the distorted surface normals against a virtual lighting environment (simulated HDRI reflection). Specular highlights will be intense and sharp, while shadows will deepen into dark bronze/amber to simulate subsurface depth within the liquid metal.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Quantum Liquid-Gold Cymatic-Vortex
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Vortex Speed, .y = Viscosity, .z = Cymatic Intensity, .w = Gold Purity
  ripples: array<vec4<f32>, 50>,
};

// ... (Constants, Noise functions, SDFs, Raymarching loop, Shading, Main compute entry)
```

Parameters (for UI sliders)
Vortex Speed (1.0, 0.1, 5.0, 0.1)
Viscosity (0.5, 0.0, 1.0, 0.05)
Cymatic Intensity (0.8, 0.0, 2.0, 0.1)
Gold Purity (1.0, 0.5, 1.5, 0.05)
