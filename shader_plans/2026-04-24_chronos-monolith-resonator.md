# New Shader Plan: Chronos Monolith Resonator

## Overview
A hyper-dimensional, endlessly shifting obelisk of quantum dark-matter suspended in a cosmic void, projecting glowing ribbons of temporal energy that ripple and distort in sync with unseen gravitational waves.

## Features
- Colossal, procedurally generated dark-matter monolith using KIFS fractals.
- Orbiting ribbons of luminescent temporal plasma that dynamically weave around the structure.
- Audio-reactive gravitational distortions (`u.config.y`) that ripple through the monolith's surface.
- Hyper-refractive internal crystal core visible through shifting fractures.
- Smooth-min (smin) blending for organic, fluid-like transitions between sharp geometry and soft plasma.

## Technical Implementation
- File: public/shaders/gen-chronos-monolith-resonator.wgsl
- Category: generative
- Tags: ["cosmic", "quantum", "mechanical", "raymarching", "kifs"]
- Algorithm: Raymarching through a KIFS-fractal monolith with volumetric plasma ribbons and domain-warped gravitational distortions.

### Core Algorithm
Raymarching with an SDF scene. The monolith is formed by folding space (KIFS) on a base cuboid structure, with an inner refractive core SDF. The temporal ribbons are swept-splines or twisted cylinders with volumetric accumulation along the ray path, using 3D simplex noise for organic movement.

### Mouse Interaction
The mouse (`u.mouse` / `u.zoom_config.y`, `u.zoom_config.z`) controls the orbital camera angle and influences a subtle gravity well, bending the plasma ribbons towards the cursor's mapped coordinates in 3D space.

### Color Mapping / Shading
The monolith uses dark, highly polished obsidian-like shading with sharp specular highlights. The inner core and temporal ribbons utilize a dynamic chromatic palette (cyan, violet, and gold) with volumetric subsurface scattering and bloom to create an ethereal glow.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Chronos Monolith Resonator
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
// ... (full skeleton with comments)
```

## Parameters (for UI sliders)

Name (default, min, max, step)
- Temporal Flow Speed (1.0, 0.1, 5.0, 0.1)
- Plasma Density (0.5, 0.0, 1.0, 0.05)
- Monolith Complexity (3.0, 1.0, 8.0, 1.0)
- Core Resonance (0.8, 0.0, 2.0, 0.1)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
