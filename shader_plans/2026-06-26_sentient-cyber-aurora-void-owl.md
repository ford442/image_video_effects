# New Shader Plan: Sentient Cyber-Aurora Void-Owl

## Overview
A hyper-majestic, biomechanical owl forged from shattered quantum glass and glowing liquid-aurora, gliding silently through a massive volumetric particle-storm void while its piercing, sonic-reactive eyes scan the darkness for fractured aether.

## Features
- Intricate Cyber-Glass Feathers: Hundreds of overlapping, semi-transparent geometric feathers that refract light and rotate dynamically using advanced domain repetition.
- Piercing Quantum-Plasma Eyes: Twin, hyper-dense glowing orbs that violently dilate and shift their spectrum from deep violet to blinding cyan based on heavy bass frequencies.
- Volumetric Aurora-Storm: A swirling, computational heavy background of twisting aurora borealis ribbons that act as a liquid atmosphere.
- Aether-Glimmer Dust: A delicate, swirling particle system that emits trails of light and is gravitationally pulled toward the owl's wingbeats.
- Time-Dilation Ripple Wings: The beating wings emit localized spatial distortions, bending the light of the background void using smooth-min SDF perturbations.

## Technical Implementation
- File: public/shaders/gen-sentient-cyber-aurora-void-owl.wgsl
- Category: generative
- Tags: ["cosmic", "owl", "quantum", "mechanical", "organic", "audio-reactive", "volumetric"]
- Algorithm: Advanced raymarching utilizing multi-layered geometric folding for the feathers, combined with a volumetric density integrator for the aurora storm background.

### Core Algorithm
- The owl's central body uses smooth-min spheres and capsules to form an organic base, overlaid with a complex lattice of hard-edged, rotated prisms (feathers) created through recursive domain mapping.
- The quantum-plasma eyes are highly emissive spheres nested inside larger refractive glass spheres, modulated by high-frequency 3D noise for a turbulent plasma effect.
- The volumetric aurora background is generated using 3D value noise accumulated along the ray path, mapped to a shifting color palette and distorted by a temporal sine function.
- The aether-glimmer dust uses particle instancing or a highly repreated volumetric point field driven by curl noise.

### Mouse Interaction
- Moving the mouse acts as a directional focal point, causing the owl's massive head to smoothly track the cursor while the wingbeat rhythm adjusts to the distance.
- Clicking sends a ripple through the void, temporarily dispersing the aurora ribbons and sending the aether-glimmer dust scattering in chaotic patterns.

### Color Mapping / Shading
- The biomechanical feathers use a complex refractive glass material model (simulated via view-angle-dependent IOR and chromatic aberration) with a sleek obsidian underlayer.
- The eyes and aether dust are pure HDR emissive, mapped to `u.zoom_params` to bloom intensely in response to audio input.
- The aurora storm uses a multi-stop color gradient blending from deep cosmic black to ethereal green, magenta, and cyan.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Sentient Cyber-Aurora Void-Owl
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
// Wingbeat Speed (1.0, 0.1, 3.0, 0.1)
// Eye Intensity (1.0, 0.5, 5.0, 0.1)
// Aurora Density (0.7, 0.1, 2.0, 0.05)
// Glass Refraction (0.8, 0.0, 1.0, 0.05)

// ----------------------------------------------------------------
// Integration Steps
// ----------------------------------------------------------------
// Create shader file
// Create JSON definition
// Run generate_shader_lists.js
// Upload via storage_manager
```
