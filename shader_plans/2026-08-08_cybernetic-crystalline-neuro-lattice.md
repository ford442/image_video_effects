# New Shader Plan: Cybernetic Crystalline Neuro-Lattice

## Overview
A hyper-structured, ever-evolving neural lattice that crystallizes data streams into neon-infused geometries, blending organic synaptic growth with cybernetic precision.

## Features
- Dynamic dendritic growth mimicking neural pathways
- Glowing crystalline nodes pulsing with data bursts
- Chromatic aberration and glitch-art reflections along geometric edges
- Fluid domain folding creating infinite recursive structures
- Subsurface scattering effect on the translucent cyber-crystals
- Reaction-diffusion patterns mapping onto the crystalline surfaces

## Technical Implementation
- File: public/shaders/gen-cybernetic-crystalline-neuro-lattice.wgsl
- Category: generative
- Tags: ["cybernetic", "crystal", "neural", "lattice", "organic", "neon"]
- Algorithm: Raymarching through a folded domain of gyroid-like structures combined with iterated function systems (IFS) for the crystalline facets.

### Core Algorithm
Raymarching using an SDF that combines a smooth, organic gyroid base with sharp, faceted crystalline structures generated via IFS folding. The space is repeatedly folded to create an infinitely dense neuro-lattice. A reaction-diffusion-like noise modulates the emission of the nodes.

### Mouse Interaction
The mouse cursor acts as a localized data surge. Moving the mouse bends the lattice towards the cursor, while clicking triggers a high-frequency shockwave that scatters the chromatic glitch effects outward from the interaction point.

### Color Mapping / Shading
A sleek, dark, obsidian-like base material with vibrant neon (cyan, magenta, electric blue) emissions at the vertices and edges. Deep subsurface scattering gives the crystals a semi-transparent, luminous quality.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Cybernetic Crystalline Neuro-Lattice
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
  zoom_params: vec4<f32>,  // .x = Point Density, .y = Rotation Speed, .z = Point Size, .w = Color Shift
  ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```

## Parameters (for UI sliders)
- Node Density (0.5, 0.1, 1.0, 0.05) - Mapped to `zoom_params.x`
- Growth Speed (0.3, 0.0, 1.0, 0.01) - Mapped to `zoom_params.y`
- Glitch Intensity (0.2, 0.0, 1.0, 0.05) - Mapped to `zoom_params.z`
- Neon Hue Shift (0.0, 0.0, 1.0, 0.01) - Mapped to `zoom_params.w`
