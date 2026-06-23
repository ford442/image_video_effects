# New Shader Plan: Radiant Cyber-Chrono Void-Stag

## Overview
A majestic, colossal cybernetic space-stag gracefully leaping through an endless, volumetric deep-space nebula, its bioluminescent cyber-antlers forging crystalline pathways of temporal energy that geometrically pulse with ambient cosmic acoustics.

## Features
- Majestic Cybernetic Space-Stag: A hyper-organic, biomechanical exoskeleton constructed using fractal geometries and smooth minimum SDFs.
- Crystal-Tension Antlers: The antlers are forged from branching, refractive chrono-crystals that visibly distort the fabric of space-time around them.
- Bioluminescent Aether Trails: Glowing, liquid-neon plasma trails seamlessly shed from the stag's hooves as it bounds through the void.
- Acoustic Resonance Core: A pulsing, liquid-chrome heart visible within its transparent thorax, beating and expanding fiercely in response to bass drops.
- Volumetric Stardust Void: The entity floats within a dense, computationally intensive volumetric nebula lit by scattered auroral bio-fluorescence.

## Technical Implementation
- File: public/shaders/gen-radiant-cyber-chrono-void-stag.wgsl
- Category: generative
- Tags: ["cosmic", "stag", "quantum", "crystal", "organic", "mechanical", "audio-reactive"]
- Algorithm: Advanced raymarching of complex SDFs with multi-domain folding, smooth min blending, and volumetric density accumulation for the aether trails and nebula.

### Core Algorithm
- Uses an advanced gyroid-based volumetric raymarcher driven by fractional Brownian motion to generate the volumetric nebula background.
- The stag's body is composed of merged capsule, ellipsoid, and torus SDFs with smooth minimums (`smin`), displaced by multi-octave 3D noise for a biomechanical texture.
- The antlers utilize an L-system-inspired branching SDF combined with a twisted domain space (`p.xy *= rot(...)`), featuring faux-refraction calculated from the SDF normal.
- The aether trails from the hooves are simulated using a time-delayed displacement along the negative Z-axis, driven by smoothstep-filtered simplex noise.

### Mouse Interaction
- The mouse acts as a gravitational chrono-flare. Orbiting the mouse rotates the global viewing matrix of the stag.
- Mouse clicks trigger a localized burst of aether-plasma around the cursor, rippling outward and causing the stag's antlers to glow intensely as they align with the gravitational pull.

### Color Mapping / Shading
- The stag's metallic exoskeleton uses a physically-inspired shading model with high specular highlights, bouncing ambient nebula light.
- The crystalline antlers employ a faux-refraction technique by distorting the background raymarch coordinates based on the surface normal.
- Emissive elements (heart, hoof trails) use deep neon color palettes (cyan/magenta/gold) that multiply their intensity based on the `u.zoom_params` (audio reactivity vectors).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Radiant Cyber-Chrono Void-Stag
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
// Stag Scale (1.0, 0.5, 2.0, 0.1)
// Antler Complexity (3.0, 1.0, 5.0, 0.1)
// Nebula Density (0.5, 0.1, 1.0, 0.05)
// Core Pulse Intensity (1.0, 0.0, 5.0, 0.1)

// ----------------------------------------------------------------
// Integration Steps
// ----------------------------------------------------------------
// Create shader file
// Create JSON definition
// Run generate_shader_lists.js
// Upload via storage_manager
```
