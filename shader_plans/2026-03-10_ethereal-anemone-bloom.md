# New Shader Plan: Ethereal Anemone Bloom

## Overview
A pulsating, infinite underwater expanse of translucent, bioluminescent anemone-like structures that gently sway in an invisible current, reaching out to "feed" on the audio frequencies.

## Features
- Soft Volumetric Tentacles: Smooth blending of organic geometry to create dense clusters of swaying tendrils.
- Subsurface Scattering Approximation: Deep, fleshy inner glows that catch light from neighboring bioluminescent nodes.
- Bioluminescent Audio-Pulse: Tips of the anemones flare with intense neon light driven directly by the audio amplitude.
- Mouse Current Disturbance: The cursor creates a localized eddy, causing the tendrils to violently whip away or get sucked toward the vortex.
- Endless Organic Topography: FBM noise layered over an infinite repeating grid to create a varied, hilly seabed.

## Technical Implementation
- File: public/shaders/gen-ethereal-anemone-bloom.wgsl
- Category: generative
- Tags: ["organic", "bioluminescent", "underwater", "fluid", "audio-reactive"]
- Algorithm: Raymarching with heavily smoothed capped cones, FBM displacement for "underwater current" sway, and domain repetition (opRep).

### Core Algorithm
The scene uses raymarching over an infinite domain (`opRep`). The primary SDFs are multiple overlapping, heavily smoothed (`smin`) capped cones bent by a sine-wave function over time to simulate a fluid current. Fractional Brownian Motion (FBM) is used to perturb the base plane, creating rolling dunes on which the anemones anchor.

### Mouse Interaction
The `u.mouse` coordinates map to a 3D gravity/vortex field. When the raymarching position nears the mouse's projected 3D space, an inverse-distance distortion function is applied to the vertex positions of the anemone tentacles, bending them sharply along the XZ plane to simulate a turbulent eddy.

### Color Mapping / Shading
Materials use a cheap subsurface scattering trick: sampling the SDF slightly deeper into the surface (`p - normal * 0.1`) and adding that inverted distance to the emissive term. The tips of the tentacles use a sharp gradient that glows intensely based on `u.config.y` (the audio accumulator), shifting colors between deep cyan and electric magenta. A heavy distance-based volumetric fog gives the deep-ocean feel.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Ethereal Anemone Bloom
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// SDF Primitives
// smin (Polynomial smooth minimum)
// sdCappedCone
// opRep (Domain Repetition)

// Helpers
// rot2D (2D Rotation Matrix)
// hash33 (3D Noise)
// fbm (Fractional Brownian Motion)

// Map Function
// - Applies infinite domain repetition for the seabed.
// - Distorts spatial coordinates (p) using time-based sine waves and FBM for the "sway".
// - Bends coordinates near u.mouse to simulate the current eddy.
// - Returns vec2(distance, material_id).

// Lighting & Shading
// - Computes normals.
// - Calculates fake subsurface scattering.
// - Injects bioluminescent emissive light at the tentacle tips scaled by u.config.y (audio pulse).

// Compute Shader Entry Point
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // 1. Ray setup and camera matrix
    // 2. Raymarching loop (break on max distance or hit)
    // 3. Shading and color accumulation
    // 4. Volumetric fog application
    // 5. writeTexture update
}
```

## Parameters (for UI sliders)

Current Speed (1.0, 0.1, 5.0, 0.1)
Tentacle Density (0.5, 0.1, 1.0, 0.05)
Bioluminescence Glow (2.0, 0.5, 5.0, 0.1)
Water Murkiness (0.8, 0.0, 1.5, 0.05)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-03-10_ethereal-anemone-bloom.md" "Ethereal Anemone Bloom"
Reply with only: "✅ Plan created and queued: 2026-03-10_ethereal-anemone-bloom.md"
