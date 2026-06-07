# New Shader Plan: Fractal Bioluminescence Spore-Network

## Overview
A hyper-organic, slowly expanding fractal network of glowing bioluminescent spores that mathematically bloom and connect via glowing filaments in response to audio frequencies.

## Features
- Infinite self-replicating fractal spore colonies
- Audio-reactive spore blooming and filament connectivity
- Bioluminescent subsurface scattering for organic translucency
- Procedural noise-driven organic drift and growth
- KIFS (Kaleidoscopic IFS) based underlying network structure
- Dynamic color palette that shifts based on growth density
- Mouse-interactive chemical injection that sparks sudden localized rapid growth

## Technical Implementation
- File: public/shaders/gen-fractal-bioluminescence-spore-network.wgsl
- Category: generative
- Tags: ["fractal", "organic", "bioluminescence", "audio-reactive", "network", "kifs"]
- Algorithm: Raymarched KIFS fractals interwoven with 3D simplex noise, utilizing a multi-pass approach (simulated via time/feedback) for glowing filament paths.

### Core Algorithm
Utilizes a Kaleidoscopic Iterated Function System (KIFS) to generate the fundamental network branching structure. The resulting distance field is then modulated heavily by 3D simplex noise to break the rigid symmetry and give it an organic, fleshy/fungal appearance. Spores are spawned at local minimums of the SDF.

### Mouse Interaction
The mouse acts as a localized nutrient injection point. A gravity well formula (`1.0 / (1.0 + distance(uv, mouse) * 10.0)`) amplifies local fractal iteration counts and rapidly increases local spore luminescence, simulating rapid fungal blooming.

### Color Mapping / Shading
Organic shading pipeline simulating subsurface scattering. The core of the spores will burn hot white/cyan, fading out to deep bioluminescent greens and blues. A bloom pass is simulated via accumulation and heavy glowing falloff.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Fractal Bioluminescence Spore-Network
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// ... (remaining shader logic will be implemented here)
```

## Parameters (for UI sliders)

- Spore Density (default: 0.5, min: 0.1, max: 1.0, step: 0.05)
- Network Complexity (default: 4.0, min: 1.0, max: 10.0, step: 1.0)
- Bioluminescence Intensity (default: 1.2, min: 0.0, max: 3.0, step: 0.1)
- Audio Reactivity (default: 0.8, min: 0.0, max: 2.0, step: 0.1)

## Integration Steps

- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
