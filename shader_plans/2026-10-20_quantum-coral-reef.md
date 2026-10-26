# New Shader Plan: Quantum Coral Reef

## Overview
A mesmerizing, bioluminescent deep-sea ecosystem that grows fractally, responding to unseen quantum currents and user interaction.

## Features
- Ethereal, organic, fractal geometry mimicking coral growth
- Dynamic bioluminescence mapping that pulses over time
- Quantum distortion waves that ripple through the structure
- Audio-reactive blooming and particle emission (treble/mids mapping)
- Mouse interaction that creates localized gravitational "heat vents" that warp the coral
- Subsurface scattering effect for organic translucency
- Procedural noise fields simulating underwater caustics and sediment

## Technical Implementation
- File: public/shaders/gen-quantum-coral-reef.wgsl
- Category: generative
- Tags: ["organic", "fractal", "bioluminescent", "underwater", "audio-reactive"]
- Algorithm: Raymarching an SDF that combines a fractal formula (Mandelbulb/KIFS hybrid) with domain repetition, perturbed by 3D simplex noise to create organic growth patterns.

### Core Algorithm
Raymarching a specialized SDF. The base structure is built using a KIFS (Kaleidoscopic Iterated Function System) fractal, heavily modified with smooth minimums (`smin`) and 3D Voronoi noise to soften hard edges into organic, branching, coral-like shapes. Space is domain-folded to repeat the coral structures infinitely, creating a vast "reef".

### Mouse Interaction
The mouse acts as a deep-sea thermal vent. When clicked (`u.zoom_config.w > 0.5`), it generates a localized gravity well and thermal distortion field. The distortion formula twists the SDF domain around the mouse world-space coordinate using a smoothstep-based falloff, pulling the coral structures towards the cursor while increasing their "heat" (luminescence).

### Color Mapping / Shading
Uses a complex palette based on depth and surface normal. Base color is deep oceanic blue/teal, with highlights shifting to vibrant neon pinks, cyans, and greens based on 3D noise (bioluminescence). Fake subsurface scattering is achieved by sampling the SDF at a few points behind the surface along the view ray. Emissive bloom is added to the bioluminescent parts.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Quantum Coral Reef
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// ... (full skeleton with comments)
```

Parameters (for UI sliders)

Name (default, min, max, step)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
