# New Shader Plan: Liquid-Neon Cyber-Metropolis

## Overview
An infinite, gravity-defying cyberpunk cityscape constructed from rivers of hyper-luminescent liquid neon and dark matter concrete, where architectural monoliths dynamically extrude, twist, and warp their geometry to the rhythm of heavy audio frequencies.

## Features
- Infinite, raymarched procedural cityscape using domain repetition and KIFS-folded megastructures.
- Buildings composed of dark matter concrete with intensely glowing, audio-reactive liquid neon veins.
- Rhythmic geometry extrusion where skyscrapers grow and retract like graphic equalizers to the audio amplitude.
- A sweeping "radar-scan" light effect that washes over the city, revealing hidden holographic infrastructure.
- Interactive gravity wells: mouse position warps the city grid, causing buildings to arc and bend towards the cursor.
- Atmospheric volumetric fog and neon bloom that dynamically shifts color palettes based on sound complexity.
- Liquid neon reflections mapped onto the dark matter surfaces, creating a hyper-reflective, rain-slicked aesthetic.

## Technical Implementation
- File: public/shaders/gen-liquid-neon-cyber-metropolis.wgsl
- Category: generative
- Tags: ["cyberpunk", "neon", "cityscape", "audio-reactive", "raymarching", "kifs"]
- Algorithm: Raymarching with 2D infinite domain repetition for the city grid, KIFS folds for architectural detailing, and smooth-min blending for the neon veins.

### Core Algorithm
The scene relies on a raymarched distance field. The XZ plane is partitioned using `opRep` (infinite domain repetition) to create city blocks. Inside each cell, a base box SDF forms the skyscraper. A time-varying, audio-linked (`u.config.y`) height modifier scales the boxes. KIFS (Kaleidoscopic Iterated Function System) folding is applied to the upper sections to create intricate, antenna-like structures. Smooth subtraction is used to carve out the glowing neon veins.

### Mouse Interaction
The mouse position (`u.zoom_config.y`, `u.zoom_config.z`) dictates the center of a localized gravitational warp. As rays pass near this coordinate, space is bent using a spherical distortion formula, causing buildings to curve inward, mimicking a black hole's lensing effect on the city grid.

### Color Mapping / Shading
The shading utilizes a base albedo of dark, specular "concrete" with high roughness. The neon veins are isolated using an SDF threshold and colored with a hyper-chromatic gradient (cyan to magenta) that shifts with time and audio. A volumetric glow pass accumulates along the ray steps, adding a heavy bloom to the neon elements.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Liquid-Neon Cyber-Metropolis
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Neon Intensity, y=City Density, z=Audio Reactivity, w=Gravity Warp Strength
    ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```

Parameters (for UI sliders)

Name (default, min, max, step)
- `u.zoom_params.x`: Neon Intensity (1.5, 0.0, 5.0, 0.1)
- `u.zoom_params.y`: City Density (10.0, 5.0, 20.0, 1.0)
- `u.zoom_params.z`: Audio Reactivity (1.0, 0.0, 3.0, 0.1)
- `u.zoom_params.w`: Gravity Warp Strength (0.5, 0.0, 2.0, 0.05)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-04-19_liquid-neon-cyber-metropolis.md" "Liquid-Neon Cyber-Metropolis"
Reply with only: "✅ Plan created and queued: 2026-04-19_liquid-neon-cyber-metropolis.md"
