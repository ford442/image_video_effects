# New Shader Plan: Cymatic Chronos Aether-Lattice

## Overview
A hyper-dimensional shifting crystalline lattice shaped by resonant audio frequencies that fold and weave through time itself.

## Features
- Evolving 4D aetherial lattice structure reacting to the beat and frequencies.
- Real-time folding of the space using chronological offset matrices.
- Sound-driven geometric fracturing revealing luminescent core energies.
- Volumetric subsurface scattering for the aetherial crystalline material.
- Smooth min (smin) transitions between interconnected fractal nodes.
- Gravity well interactions driven by precise cursor distortion formulas.
- Audio-reactive color mapping highlighting stress points in the lattice.

## Technical Implementation
- File: public/shaders/gen-cymatic-chronos-aether-lattice.wgsl
- Category: generative
- Tags: ["crystalline", "cymatic", "audio-reactive", "time-folding", "fractal"]
- Algorithm: Raymarching through domain-repeated 4D SDFs (simulated via 3D + time rotation) perturbed by audio-modulated cellular noise.

### Core Algorithm
Raymarching a boundless lattice of interconnected spheres and capsules. The coordinates are folded using a hyper-dimensional rotation matrix modulated by `u.config.x` (time) and audio frequencies sampled from `dataTextureC`. High frequencies trigger sharp geometric fractures (sharp boolean subtractions), while low frequencies smoothly expand the lattice.

### Mouse Interaction
The mouse (`u.zoom_config.yz`) establishes an interactive gravity well in the center of the viewport. As the user moves the mouse, the space bends using a quadratic distortion formula (`distortion = 1.0 / (1.0 + length(p - mouse_pos) * gravity_strength)`), pulling the lattice towards the cursor and bending the underlying light rays.

### Color Mapping / Shading
A high-dynamic-range gradient mapped from deep obsidian and sapphire to blazing magenta and cyan at the fracture points. Blackbody-style radiation mapping combined with volumetric light integration during raymarching provides a soft, glowing subsurface bloom effect to the crystal matrices.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Cymatic Chronos Aether-Lattice
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

struct Uniforms {
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Resonance Amplitude, .y = Lattice Density, .z = Time Fold Rate, .w = Core Luminance
  ripples: array<vec4<f32>, 50>,
};
// ... (full skeleton with comments)
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Resonance Amplitude (1.0, 0.0, 5.0, 0.1)
- Lattice Density (0.5, 0.1, 1.0, 0.05)
- Time Fold Rate (1.0, 0.0, 3.0, 0.1)
- Core Luminance (2.0, 0.5, 5.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-08-15_cymatic-chronos-aether-lattice.md" "Cymatic Chronos Aether-Lattice"
Reply with only: "✅ Plan created and queued: 2026-08-15_cymatic-chronos-aether-lattice.md"
