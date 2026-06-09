# New Shader Plan: Astral-Silk Chrono-Weaver Arachnid

## Overview
A majestic, biomechanical celestial arachnid suspended in a deep cosmic void, continuously weaving an intricate, glowing fractal web of 'astral silk' out of raw quantum time-fluid, heavily reacting to bass frequencies by sending shockwaves of light through its geometric threads.

## Features
- Procedural generation of a biomechanical arachnid core using KIFS (Kaleidoscopic IFS) fractals.
- Dynamic, sprawling 'astral silk' web created via recursive Voronoi displacement and domain folding.
- Audio-reactive light pulses that travel outward along the web threads based on `u.config.y` (audio/click).
- Simulates quantum time-fluid by shifting the refraction and color-bleed of the silk threads based on `u.config.x` (time).
- Volumetric glowing plasma 'eyes' embedded in the central fractal structure.
- Cinematic depth of field blurring the distant layers of the cosmic web.
- Deep background containing slow-drifting, faint celestial dust using multi-layered noise.

## Technical Implementation
- File: public/shaders/gen-astral-silk-chrono-weaver-arachnid.wgsl
- Category: generative
- Tags: ["biomechanical", "fractal", "cosmic", "web", "audio-reactive"]
- Algorithm: Complex SDF raymarching combining a heavily folded KIFS fractal for the central entity and a highly distorted, thin-lattice Voronoi structure for the glowing web.

### Core Algorithm
The central entity is modeled via a fold-based Kaleidoscopic Iterated Function System (KIFS) SDF, creating complex, sharp biomechanical legs and a central thorax. The web is generated using an inverted, extremely thin 3D Voronoi noise to create a lattice of threads. The distance to these threads is used to emit light volumetrically. Both SDFs are blended using smooth minimums to root the web organically into the arachnid's structure.

### Mouse Interaction
The mouse (`u.zoom_config.y`, `u.zoom_config.z`) controls the orbit of the camera around the central entity. As the mouse moves closer to the center, it acts as a gravitational lens, bending the surrounding web threads inward and intensifying their brightness to simulate a dense cluster of quantum energy.

### Color Mapping / Shading
The central entity features a dark, liquid-obsidian metallic shading with high specularity. The astral silk threads are highly emissive, shifting through a spectrum of deep purples, electric blues, and vivid magentas. Audio impulses create a high-intensity, bright-white 'shockwave' that maps along the radius of the Voronoi lattice.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Astral-Silk Chrono-Weaver Arachnid
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
// ... (full skeleton with comments)

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Web Density, y=Pulse Speed, z=Entity Scale, w=Glow Intensity
    ripples: array<vec4<f32>, 50>,
};

// Parameters (for UI sliders)
// Web Density (2.5, 1.0, 5.0, 0.1)
// Pulse Speed (1.0, 0.1, 3.0, 0.1)
// Entity Scale (1.0, 0.5, 2.0, 0.1)
// Glow Intensity (1.5, 0.1, 5.0, 0.1)
```

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
