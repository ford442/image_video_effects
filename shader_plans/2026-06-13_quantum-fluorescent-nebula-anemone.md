# New Shader Plan: Quantum-Fluorescent Nebula-Anemone

## Overview
A hyper-organic, glowing cosmic sea-anemone suspended in a volumetric deep-space nebula, whose translucent quantum tentacles ripple and mathematically divide in perfect sync with ambient acoustic frequencies.

## Features
- Volumetric deep-space nebula rendering using raymarched fractional Brownian motion.
- Hyper-organic procedural anemone tentacles generated via curved, twisting SDFs and polar repetition.
- Subsurface scattering simulation for a translucent, gelatinous plasma aesthetic.
- Audio-reactive tentacle undulation driven by acoustic bass frequencies.
- Quantum-fluorescent bioluminescence that shifts across the chromatic spectrum based on temporal energy.
- Interactive gravity wells from mouse inputs causing tentacles to violently flock toward the cursor.

## Technical Implementation
- File: public/shaders/gen-quantum-fluorescent-nebula-anemone.wgsl
- Category: generative
- Tags: ["organic", "nebula", "quantum", "particles", "audio-reactive"]
- Algorithm: Raymarching with domain-warped SDFs for organic tentacle structures, combined with volumetric noise for the surrounding nebula field.

### Core Algorithm
The anemone is modeled using a central sphere SDF with multiple sweeping, tapered cylinder SDFs radially repeated using `atan2` and polar coordinates. The tentacles' twisting motion is achieved by domain warping the SDF inputs using sine waves modulated by the `u.config.y` uniform and time. The surrounding nebula is rendered using a low-iteration fBM noise loop that accumulates density along the ray path.

### Mouse Interaction
The `u.zoom_config.y` and `u.zoom_config.z` uniforms act as a localized gravity well. Rays within a certain distance of the projected mouse coordinates experience a spatial bend, causing the tentacles to stretch and lean towards the cursor.

### Color Mapping / Shading
The anemone uses a custom subsurface scattering approximation by sampling the SDF multiple times along the light vector. Colors map `u.zoom_params.x` to a glowing neon gradient (cyan to deep magenta). The nebula background adds a soft additive blend using a multi-frequency noise field.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Quantum-Fluorescent Nebula-Anemone
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

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

// Additional noise and SDF functions go here

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // Raymarching and rendering logic
}
```

## Parameters (for UI sliders)

- Fluorescence Intensity (0.5, 0.0, 1.0, 0.01)
- Tentacle Density (0.5, 0.0, 1.0, 0.01)
- Audio Reactivity (0.5, 0.0, 1.0, 0.01)
- Nebula Density (0.5, 0.0, 1.0, 0.01)

## Integration Steps

- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
