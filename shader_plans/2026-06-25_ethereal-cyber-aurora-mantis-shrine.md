# New Shader Plan: Ethereal Cyber-Aurora Mantis-Shrine

## Overview
A majestic, hyper-organic cyber-mantis meditating within a colossal, glowing quantum lotus floating in a deep-space nebula, its biomechanical limbs interlaced with bioluminescent auroral threads that pulse furiously in rhythm with cosmic frequencies.

## Features
- Zen Cyber-Mantis: A hyper-detailed biomechanical entity blending sharp insectoid angles with fluid liquid-chrome joints.
- Quantum Lotus Pedestal: A recursively unfolding fractal lotus made of pure auroral plasma that supports the mantis.
- Bioluminescent Neuro-Filaments: Glowing cyan and magenta threads connecting the mantis's appendages to the lotus petals, transferring acoustic energy.
- Acoustic Heart-Pulse: The mantis’s transparent thorax houses an intricate fractal crystal that beats violently in sync with deep bass drops.
- Volumetric Aether Mist: A slow-drifting, highly volumetric nebula background rendered using multi-octave FBM, illuminated by the glowing lotus.

## Technical Implementation
- File: public/shaders/gen-ethereal-cyber-aurora-mantis-shrine.wgsl
- Category: generative
- Tags: ["cosmic", "mantis", "quantum", "lotus", "organic", "mechanical", "audio-reactive"]
- Algorithm: Advanced raymarching of complex SDFs with multi-domain folding for the lotus, smooth minimum blending for the biomechanical mantis, and volumetric density accumulation for the aether mist.

### Core Algorithm
- Uses an advanced gyroid-based volumetric raymarcher driven by fractional Brownian motion to generate the volumetric aether mist background.
- The cyber-mantis is composed of merged capsule, ellipsoid, and torus SDFs with smooth minimums (`smin`), bent and distorted using non-linear space transformations to create sharp biomechanical limbs and fluid joints.
- The quantum lotus uses a highly recursive L-system fractal combined with 2D rotational domain repetition (`p.xy *= rot(...)`), blooming outward based on trigonometric time functions.
- The neuro-filaments are simulated using a time-delayed displacement along the Z-axis, driven by smoothstep-filtered simplex noise, connecting the mantis to the lotus structure.

### Mouse Interaction
- The mouse acts as a gravitational aether-node. Orbiting the mouse rotates the global viewing matrix of the shrine.
- Mouse clicks trigger a localized burst of aether-plasma around the cursor, rippling outward and causing the lotus petals to unfold more rapidly and glow intensely.

### Color Mapping / Shading
- The mantis's liquid-chrome exoskeleton uses a physically-inspired shading model with high specular highlights, reflecting the ambient glow of the lotus.
- The quantum lotus employs a volumetric emission model, layering deep neon cyan and magenta palettes.
- Emissive elements (heart-pulse, neuro-filaments) multiply their intensity based on the `u.zoom_params` (audio reactivity vectors), creating a stunning visual reaction to sound.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Ethereal Cyber-Aurora Mantis-Shrine
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

// ----------------------------------------------------------------
// Parameters (for UI sliders)
// ----------------------------------------------------------------
// Name (default, min, max, step)
// Mantis Scale (1.0, 0.5, 2.0, 0.1)
// Lotus Complexity (3.0, 1.0, 5.0, 0.1)
// Mist Density (0.5, 0.1, 1.0, 0.05)
// Core Pulse Intensity (1.0, 0.0, 5.0, 0.1)

// ----------------------------------------------------------------
// Integration Steps
// ----------------------------------------------------------------
// Create shader file
// Create JSON definition
// Run generate_shader_lists.js
// Upload via storage_manager
```