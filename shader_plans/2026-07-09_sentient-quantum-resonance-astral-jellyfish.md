# New Shader Plan: Sentient Quantum-Resonance Astral-Jellyfish

## Overview
A hyper-organic, bioluminescent astral-jellyfish composed of shifting quantum resonance fields drifts through a dynamic particle-storm void, its crystalline tentacles plucking the acoustic frequencies of the cosmos.

## Features
- Volumetric quantum-resonance body that undulates with time and audio frequencies.
- Crystalline temporal tentacles that leave glowing trail artifacts through the void.
- Subsurface scattering simulation for a translucent, liquid-plasma bell.
- Reactive acoustic-driven lighting that shifts colors from cyan to deep neon pink.
- Mouse-driven gravity wells that attract or repel the jellyfish's drifting particle-spores.
- Background deep-space nebula built from layered fractal noise and chromatic aberration.

## Technical Implementation
- File: public/shaders/gen-sentient-quantum-resonance-astral-jellyfish.wgsl
- Category: generative
- Tags: ["organic", "quantum", "cosmic", "particle systems", "audio-reactive"]
- Algorithm: Raymarching combined with domain warping, fractal Brownian motion (fBm) for the nebula, and distance field manipulation for the jellyfish.

### Core Algorithm
Raymarching an SDF representing the jellyfish bell (a modified parabolic/dome SDF) and its tentacles (splines defined by sine waves and time). Volumetric rendering integrates fBM noise across the steps to create a dense, ethereal glow around the body, mapping acoustic peaks (from `u.config.y`) to the density and emission strength.

### Mouse Interaction
The mouse (`u.zoom_config.y` and `u.zoom_config.z`) defines a point source in 2D projected space. Tentacles curl toward the mouse position, and background particles (or noise turbulence) form a gentle gravity well, warping space around the cursor using a smooth inverse-square attenuation.

### Color Mapping / Shading
Uses a highly customized ACES tone-mapping curve. Subsurface scattering is faked using a combination of rim lighting and thickness approximation (from raymarching step accumulation). Gradient mapping transitions from ethereal cyan-blue in the center to neon pink on the fringes as acoustic input increases.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Sentient Quantum-Resonance Astral-Jellyfish
// Category: generative
// ----------------------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
    ripples: vec4<f32>,      // Ripples requirement
};

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

// Utility functions
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn map(p: vec3<f32>) -> f32 {
    let time = u.config.x;
    let audio = u.config.y;
    // SDF logic for jellyfish
    var q = p;
    q.y += sin(time + q.x * 2.0) * 0.2 * audio;
    let bell = length(q) - 1.0;
    return bell;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let uv = vec2<f32>(f32(id.x), f32(id.y)) / vec2<f32>(u.config.z, u.config.w);
    let time = u.config.x;
    let audio = u.config.y;

    // Raymarching setup and execution
    var color = vec3<f32>(0.0);
    // ... main rendering loop ...

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(color, 1.0));
}
```

Parameters (for UI sliders)

Quantum Resonance (0.5, 0.0, 1.0, 0.01)
Tentacle Length (1.0, 0.1, 2.0, 0.05)
Nebula Density (0.3, 0.0, 1.0, 0.01)
Acoustic Sensitivity (0.8, 0.0, 2.0, 0.1)
