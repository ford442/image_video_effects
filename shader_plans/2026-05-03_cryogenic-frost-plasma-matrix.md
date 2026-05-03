# New Shader Plan: Cryogenic Frost-Plasma Matrix

## Overview
An infinitely shattering and reforming matrix of absolute-zero hyper-fractals that bleed iridescent thermal plasma when fractured by heavy bass frequencies.

## Features
- **Sub-Zero KIFS Fractals:** Utilizing Kaleidoscopic IFS to generate endless, sharp, crystalline spikes and icy crags.
- **Thermal Plasma Bleed:** Smooth-min (smin) intersections mapped to a glowing plasma palette, representing heat escaping from audio-induced fractures.
- **Volumetric Frost-Fog:** Raymarched volume rendering of a dense, swirling mist that accumulates in the deep valleys of the fractal structure.
- **Hyper-Refractive Glints:** Specular highlights that mimic the blinding glint of light bouncing off microscopic ice facets.
- **Dynamic Shattering:** Audio-reactive domain distortion that violently offsets coordinates, creating the illusion of the ice breaking apart.

## Technical Implementation
- File: public/shaders/gen-cryogenic-frost-plasma-matrix.wgsl
- Category: generative
- Tags: ["crystal", "ice", "plasma", "fractal", "raymarching", "audio-reactive"]
- Algorithm: Raymarching with KIFS-driven SDFs, multi-material rendering (ice vs plasma), and volumetric fog integration.

### Core Algorithm
The core scene is driven by a 3D raymarcher evaluating a signed distance field (SDF) of a heavily folded domain (using multiple KIFS iterations). The domain is periodically fractured using Voronoi noise perturbed by the bass frequencies of the audio. The SDF evaluates both the distance to the solid ice structure and a secondary 'plasma' structure that exists inside the ice.

### Mouse Interaction
The mouse controls the virtual camera's orbit around a central, shattered monolith, while the Y-axis controls the depth of focus (simulating macro lens depth-of-field effects in post-processing or altering the fog density).

### Color Mapping / Shading
- **Ice:** Translucent, high-gloss specular reflections, refractive tinting (deep cyans and pale blues).
- **Plasma:** High-emission, HDR blooming colors ranging from deep magenta to blinding neon orange, driven by the inner plasma SDF.
- **Fog:** Soft, pale blue volumetric scattering.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Cryogenic Frost-Plasma Matrix
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

// ... Raymarching constants, SDFs for KIFS and plasma, lighting, main loop ...
```

## Parameters (for UI sliders)

- Fracture Intensity (0.5, 0.0, 1.0, 0.01)
- Plasma Heat (0.8, 0.0, 2.0, 0.01)
- Ice Density (1.2, 0.1, 3.0, 0.01)
- Fog Thickness (0.3, 0.0, 1.0, 0.01)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
