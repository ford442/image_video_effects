# New Shader Plan: Holographic Bismuth-Core Reactor

## Overview
A hyper-dimensional, endlessly unfolding bismuth core reactor, merging metallic stepped-fractals with liquid-holographic interference patterns that dynamically pulse to ambient energy fields.

## Features
- Procedurally generated stepped-bismuth geometry using customized KIFS fractals.
- Iridescent interference thin-film lighting to create a shifting holographic surface.
- Inner core void that emits rhythmic, audio-reactive energy pulses.
- Volumetric glowing plasma trails swirling around the core structure.
- Orbiting iridescent micro-crystals governed by the central gravity well.

## Technical Implementation
- File: public/shaders/gen-holographic-bismuth-core-reactor.wgsl
- Category: generative
- Tags: ["cosmic", "mechanical", "kifs", "raymarching", "holographic"]
- Algorithm: 3D Raymarching utilizing a recursive folding algorithm (KIFS) adapted to create 90-degree stepped geometric structures, combined with thin-film interference formulas for iridescent coloring.

### Core Algorithm
A 3D SDF raymarcher where the primary structure is formed by iteratively folding space along multiple axes using KIFS, specifically constrained to produce right-angled, stair-stepped features characteristic of bismuth crystals. Domain repetition adds a field of floating micro-crystals. Volumetric accumulation along the ray handles the glowing plasma.

### Mouse Interaction
The mouse acts as a quantum disruption point; dragging rotates the central core and warps the gravity field (`u.config.xy`), causing the floating micro-crystals to swarm towards the interaction point and the central core to slightly expand or destabilize its fractal iterations.

### Color Mapping / Shading
Surface shading uses a thin-film interference model based on the angle of incidence (dot product of view ray and normal) and a phase shift driven by audio reactivity (`u.config.z`), producing intense, shifting rainbow/oil-slick gradients. The plasma trails are additive blended bloom with high saturation.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Holographic Bismuth-Core Reactor
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
- Core Size (0.5, 0.1, 1.0, 0.01)
- Iridescence Shift (0.0, 0.0, 1.0, 0.01)
- Pulse Intensity (0.5, 0.0, 1.0, 0.01)
- Plasma Density (0.3, 0.0, 1.0, 0.01)

## Integration Steps
- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
