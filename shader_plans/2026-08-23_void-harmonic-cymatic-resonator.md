# New Shader Plan: Void Harmonic Cymatic Resonator

## Overview
A hyper-dimensional sound-reactive sculpture that renders the visible form of acoustic frequencies in the void, resembling Chladni patterns suspended in dark matter.

## Features
- Real-time 3D cymatic wave visualization using complex frequency domains.
- Ethereal, bioluminescent color mappings that shift with wave amplitude.
- Audio-reactive standing wave nodes that pulsate to `dataTextureC`.
- Deep, dark space environment with volumetric fog fading into infinity.
- Interactive mouse gravity that warps the nodal structures.
- Smooth anti-aliasing via raymarching sub-sampling techniques.

## Technical Implementation
- File: public/shaders/gen-void-harmonic-cymatic-resonator.wgsl
- Category: generative
- Tags: ["cymatic", "audio-reactive", "raymarching", "volumetric", "fractal", "void"]
- Algorithm: 3D Raymarching with domain-folded acoustic interference patterns and distance-field modifiers.

### Core Algorithm
The SDF is based on intersecting 3D sinusoidal wave functions across three axes. The core shape is modified by adding high-frequency noise and domain repetition. We sample `dataTextureC` to modulate the frequency and amplitude of the standing waves, making the SDF dynamically react to audio input.

### Mouse Interaction
The mouse cursor acts as a localized gravitational anomaly. The formula `warp = 1.0 / (1.0 + pow(length(p - mousePos), 2.0))` is applied to the spatial coordinates `p` before evaluating the SDF, effectively bending the cymatic patterns towards the cursor.

### Color Mapping / Shading
Color is determined by the number of raymarching steps and the distance to the surface, creating a volumetric "glow" effect (subsurface scattering proxy). We use a custom color palette blending deep abyssal blues with hot neon magentas and electric cyans at the nodal points (highest wave amplitude).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Void Harmonic Cymatic Resonator
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
  zoom_params: vec4<f32>,  // .x = Frequency, .y = Amplitude, .z = Glow Intensity, .w = Complexity
  ripples: array<vec4<f32>, 50>,
};

// ... (Constants, Math Helpers, SDF logic, Audio Sampling, Main Compute Shader)
```

Parameters (for UI sliders)

Frequency (1.0, 0.1, 10.0, 0.1)
Amplitude (1.0, 0.0, 5.0, 0.1)
Glow Intensity (2.0, 0.1, 10.0, 0.1)
Complexity (3.0, 1.0, 10.0, 1.0)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
