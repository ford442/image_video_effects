# New Shader Plan: Hyper-Dimensional Tesseract-Labyrinth

## Overview
A dizzying, gravity-defying maze of glowing hyper-cubes that unfold and rotate through 4D space, creating impossible, Escher-like geometries driven by sound.

## Features
- **4D Tesseract Rotation:** Core geometries are rotated through a simulated 4th dimension, causing cubes to morph, fold, and intersect impossibly.
- **Audio-Reactive Shifts:** The labyrinth walls snap, align, and shatter to the beat of the audio (`u.config.y`), sending shockwaves of neon light through the corridors.
- **Gravity-Defying Architecture:** Infinite domain repetition in all 3 axes, creating an endless structure of shifting corridors.
- **Holographic Edges:** The structural wireframes glow with intense chromatic dispersion (RGB shifting), while the faces are semi-transparent and glassy.
- **Mouse Reality-Warp:** The mouse cursor acts as a localized gravitational anomaly, twisting the 4D rotation matrix and bending the corridors towards the viewer.

## Technical Implementation
- File: public/shaders/gen-hyper-dimensional-tesseract-labyrinth.wgsl
- Category: generative
- Tags: ["geometric", "4d", "optical-illusion", "audio-reactive", "raymarching"]
- Algorithm: 3D raymarching combined with simulated 4D rotations and infinite domain repetition.

### Core Algorithm
The environment is built using `sdBoxFrame` and `sdBox` primitives. Before evaluation, the 3D spatial coordinates are extended to a 4D vector. The coordinates undergo a 4D rotation matrix, where the 4th dimensional component `w` is modulated via `u.config.x` (time) and `u.config.y` (audio). Domain repetition expands the local geometry into an infinite grid.

### Mouse Interaction
The mouse (`u.zoom_config.y`, `u.zoom_config.z`) controls the camera orientation. Additionally, a smooth gravitational distortion field is applied to the raymarched coordinates based on their proximity to the mouse vector, causing the labyrinth to warp and bend around the cursor.

### Color Mapping / Shading
Materials use a dual-pass approach in the distance function to separate solid glass faces from emissive edges. The edges use a spatial-based sine palette to shift through intense neon spectrums, while the faces reflect ambient data-glow. Depth attenuation is handled via an exponential volumetric fog.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Hyper-Dimensional Tesseract-Labyrinth
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
    zoom_params: vec4<f32>,  // x=Tesseract Complexity, y=Edge Glow, z=Warp Field, w=Fly Speed
    ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Tesseract Complexity (1.0, 0.1, 3.0, 0.1)
- Edge Glow (2.0, 0.0, 5.0, 0.1)
- Warp Field (1.0, 0.0, 5.0, 0.1)
- Fly Speed (2.0, 0.0, 10.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-04-03_hyper-dimensional-tesseract-labyrinth.md" "Hyper-Dimensional Tesseract-Labyrinth"
Reply with only: "✅ Plan created and queued: 2026-04-03_hyper-dimensional-tesseract-labyrinth.md"