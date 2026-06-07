# New Shader Plan: Symbiotic Plasma-Reef Matrix

## Overview
A hyper-vibrant, bioluminescent deep-sea reef constructed from liquid plasma and geometric coral structures that pulsates and spawns luminescent microscopic entities in sync with audio frequencies.

## Features
- Infinite, scrolling terrain of fractal coral structures made of glowing plasma.
- Swarms of microscopic, bioluminescent entities that flock around the coral and react to sound.
- Smooth volumetric fog that simulates the deep ocean environment.
- Rhythmic expansion and contraction of the reef structures, simulating breathing.
- Dynamic color shifts based on the audio frequency spectrum (lows drive deep blues/purples, highs trigger bright cyan/green flashes).

## Technical Implementation
- File: public/shaders/gen-symbiotic-plasma-reef-matrix.wgsl
- Category: generative
- Tags: ["organic", "ocean", "bioluminescent", "plasma", "audio-reactive"]
- Algorithm: Raymarching with smooth-min blending for organic shapes and boids simulation for entities.

### Core Algorithm
The terrain is generated using raymarching over a domain-warped 3D noise function blended with geometric shapes using smooth-min (smin). The flocking entities are simulated using a separate particle update pass (or cleverly integrated using procedural noise driven by time and audio). The plasma effect is achieved via subsurface scattering approximation and bloom.

### Mouse Interaction
Mouse movement creates a gentle ripple in the water, displacing the nearby coral structures and scattering the bioluminescent entities away from the cursor.

### Color Mapping / Shading
Deep oceanic background fading into pure black. The coral features a color gradient from deep violet to vibrant pink, emitting a strong bloom effect. The entities are bright cyan and green, leaving faint trailing glows.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Symbiotic Plasma-Reef Matrix
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

// ... (full skeleton with comments)
```

## Parameters (for UI sliders)
- Reef Density: `u.zoom_params.x` (0.5, 0.1, 1.0, 0.01)
- Entity Swarm Size: `u.zoom_params.y` (0.8, 0.0, 2.0, 0.05)
- Bioluminescent Glow: `u.zoom_params.z` (0.6, 0.1, 1.5, 0.01)

## Integration Steps
- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
