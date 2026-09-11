# New Shader Plan: Liquid Neon Topography

## Overview
A mesmerizing descent into a hyper-fluid, self-illuminating digital landscape where neon currents carve through shifting, organic terrain.

## Features
- Infinite, non-repeating fluid domain based on layered fractional Brownian motion (fBm).
- High-contrast, glowing neon ridges that dynamically evolve and react over time.
- Liquid metallic subsurface scattering simulating depth and translucency in the valleys.
- A sweeping virtual camera providing an evolving, low-altitude flyover perspective.
- Audio-reactive frequency sampling driving the intensity of the topographic neon emission.
- Temporal history blending for smooth, persistent trails and fluid wake effects.

## Technical Implementation
- File: public/shaders/gen-liquid-neon-topography.wgsl
- Category: generative
- Tags: ["fluid", "neon", "topography", "fbm", "audio-reactive", "organic"]
- Algorithm: Raymarching against a complex 3D displacement map driven by 2D domain-warped noise, with layered shading to simulate emissive edges and metallic subsurface depth.

### Core Algorithm
The terrain is defined using a 2D distance function that samples multiple octaves of Simplex/Value noise (fBm). To create the organic, fluid-like ridges, domain warping is applied: the coordinates used to sample the noise are themselves offset by another noise layer. This creates sweeping, curled formations. A raymarching loop steps through this heightmap field.

### Mouse Interaction
The mouse coordinates will offset the virtual camera's focus point, creating a localized gravity well or distortion field. Specifically, the X axis will bend the global time flow mapped to the terrain's drift speed, and the Y axis will warp the domain's fundamental frequency, pulling the ridges tighter or pushing them apart.

### Color Mapping / Shading
The shading relies on a combination of a deep, dark metallic base for the valleys and intense, highly-saturated neon gradients (cyan to magenta to electric blue) mapped to the sharpest peaks and edges. The emission intensity of these neon ridges will pulse based on audio frequency data (`dataTextureC`), augmented by an HDR bloom lift.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Liquid Neon Topography
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Ridge Height, .y = Flow Speed, .z = Emissive Glow, .w = Contour Detail
  ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```

Parameters (for UI sliders)
- Ridge Height (1.0, 0.1, 5.0, 0.1)
- Flow Speed (1.0, 0.0, 3.0, 0.1)
- Emissive Glow (1.5, 0.5, 4.0, 0.1)
- Contour Detail (4.0, 1.0, 8.0, 1.0)
