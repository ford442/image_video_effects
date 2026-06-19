# New Shader Plan: Sentient Liquid-Neon Fractal-Heart

## Overview
A hyper-organic, pulsating biomechanical heart composed entirely of intertwined, liquid-neon fractal arteries that endlessly fold inward upon themselves, beating in perfect sync with ambient cosmic acoustic frequencies.

## Features
- A central, multi-chambered organic heart structure generated using deeply recursive Menger-sponge inspired SDFs combined with smooth-min blending.
- Blood vessels that appear as bright, glowing liquid-neon plasma streams traveling through translucent crystalline tissues.
- Volumetric subsurface scattering that gives the heart a fleshy, hyper-organic, yet mechanical aesthetic.
- A dynamic heartbeat cycle driven by a combination of a low-frequency sine wave and intense audio-reactive spikes (using `u.ripples`).
- Floating, microscopic quantum bio-particles circulating around the heart in the void.
- Mouse interaction that acts as a localized defribillator shock, violently contracting the fractal chambers.

## Technical Implementation
- File: public/shaders/gen-sentient-liquid-neon-fractal-heart.wgsl
- Category: generative
- Tags: ["organic", "biomechanical", "fractal", "neon", "plasma"]
- Algorithm: Volumetric raymarching of a deeply domain-warped and folded SDF structure, utilizing recursive spatial folding techniques (like the KIFS fractal) mixed with smooth volumetric accumulation for a soft, glowing, tissue-like appearance.

### Core Algorithm
- Primary domain uses recursive folding (KIFS) applied to a central bounded sphere, repeatedly mirroring and scaling space to create intricate, artery-like structures.
- A global `smin` (smooth-min) operation blends the sharp fractal edges into fluid, organic curves.
- The beating motion is achieved by globally scaling the SDF coordinates based on a simulated "pulse" function (a periodic exponential decay mixed with audio ripples).

### Mouse Interaction
- The mouse position (`u.config.xy`) creates a localized shockwave. When the mouse moves rapidly, it distorts the local space near the cursor, and if held, acts as a gravity well that pulls the fractal arteries toward it, imitating a localized defibrillator shock.
- Formula involves calculating the distance to the mouse and applying a smoothstep-based spatial displacement.

### Color Mapping / Shading
- Arteries: Saturated liquid neon (magenta and electric cyan), mapped to the distance from the core.
- Tissue: Translucent deep violet with volumetric subsurface scattering to simulate light passing through dense biological matter.
- Void: A dark, ambient bioluminescent fog.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Sentient Liquid-Neon Fractal-Heart
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
- Name: Fractal Complexity (default: 0.5, min: 0.1, max: 1.0, step: 0.01) -> maps to u.zoom_params.x
- Name: Pulse Intensity (default: 0.8, min: 0.0, max: 2.0, step: 0.01) -> maps to u.zoom_params.y
- Name: Neon Saturation (default: 0.7, min: 0.0, max: 1.5, step: 0.01) -> maps to u.zoom_params.z
- Name: Bioluminescent Fog (default: 0.4, min: 0.0, max: 1.0, step: 0.01) -> maps to u.zoom_params.w

## Integration Steps
1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
