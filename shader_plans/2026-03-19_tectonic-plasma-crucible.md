# New Shader Plan: Tectonic Plasma-Crucible

## Overview
A violently shifting landscape of cooling obsidian geometric slabs floating on a turbulent, audio-reactive ocean of blinding-hot plasma magma that constantly fractures, erupts, and reshapes itself.

## Features
- **Tectonic Slabs:** Voronoi-fractured SDF blocks representing jagged cooling obsidian crust that shifts, collides, and slowly drifts.
- **Plasma Magma Ocean:** A dense, glowing fluid beneath the crust, simulated with domain-warped FBM and intense black-body radiation color mapping.
- **Audio-Reactive Eruptions:** Sound frequencies (`u.config.y`) trigger explosive cracks in the obsidian, exposing blinding plasma flares and driving volcanic displacement spikes.
- **Heat Distortion:** Raymarching incorporates an air-shimmering heat haze effect, bending rays that pass closely over the exposed magma.
- **Mouse Tectonic Stress:** The cursor acts as a localized gravity and pressure well, forcing the crust to splinter and lava to aggressively pool around the interaction point.

## Technical Implementation
- File: public/shaders/gen-tectonic-plasma-crucible.wgsl
- Category: generative
- Tags: ["magma", "obsidian", "fractal", "lava", "audio-reactive", "tectonic"]
- Algorithm: Raymarching over a dynamic, Voronoi-displaced infinite plane SDF mixed with volumetric fluid layers.

### Core Algorithm
The environment is built on an infinite plane SDF heavily displaced by a combination of 3D FBM and cell-based Voronoi noise. The Voronoi edges define deep fissures (the magma), while the cell centers form the thick obsidian slabs. A secondary pass of high-frequency noise is subtracted from the gaps to create bubbling fluid dynamics in the lava, driven by `u.time` and audio inputs.

### Mouse Interaction
The mouse (`u.mouse`) applies a localized spatial distortion and depression to the SDF domain. When the mouse moves, it applies an inverse-square distance modifier that pushes the Voronoi cells apart, widening the fissures to reveal more of the plasma ocean beneath and increasing the glow intensity locally.

### Color Mapping / Shading
The crust uses a dark, highly specular obsidian material with micro-facet roughness. The fissures utilize a black-body radiation gradient (deep reds to blinding yellows and whites). The magma glow uses an exponential falloff to simulate sub-surface scattering and intense ambient heat, peaking during audio synchronization (`u.config.y`).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Tectonic Plasma-Crucible
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// --- NOISE & SDF FUNCTIONS ---
// fbm(), voronoi(), sdPlane()
// ...

// --- MAP FUNCTION ---
// Combines Voronoi fracturing and fluid FBM for the magma
// ...

// --- MAIN RENDER LOOP ---
// Raymarching, heat distortion bending, color mapping
// ...
```

Parameters (for UI sliders)

Crust Density (1.0, 0.1, 5.0, 0.1)
Magma Turbulence (0.5, 0.0, 2.0, 0.05)
Eruption Intensity (1.0, 0.0, 3.0, 0.1)
Tectonic Stress (1.0, 0.0, 5.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
