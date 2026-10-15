# New Shader Plan: Aetheric Tachyon Lattice

## Overview
A high-energy, multidimensional lattice of glowing tachyon streams, oscillating and folding through a non-Euclidean void.

## Features
- Intricate 3D lattice formed by recursive spatial folding
- High-frequency tachyon streams flowing along the lattice edges
- Audio-reactive stream intensity and lattice expansion
- Multi-layered chromatic dispersion and metallic shading
- Dynamic gravitational lensing around mouse interaction points

## Technical Implementation
- File: public/shaders/gen-aetheric-tachyon-lattice.wgsl
- Category: generative
- Tags: ["lattice", "tachyon", "energy", "folded-space", "audio-reactive"]
- Algorithm: Raymarching through a heavily folded SDF space with layered procedural noise for the tachyon streams.

### Core Algorithm
Raymarching a domain that is repeatedly folded using `abs()` and rotational matrices. The base SDF is an interconnected frame of thin cylinders or capsules. Tachyon streams are simulated by sampling high-frequency 3D Simplex or Voronoi noise mapped along the folded coordinates and animating them rapidly against time.

### Mouse Interaction
The mouse (`u.zoom_config.yz`) dictates the origin of a localized gravitational distortion field. When clicked (`u.zoom_config.w > 0.5`), it applies an inverse-square spherical warp to the ray directions, bending the lattice around the cursor position.

### Color Mapping / Shading
The lattice structural elements use a dark metallic BRDF approximation, while the tachyon streams emit intense, over-driven colors (cyan, magenta, and electric blue) that bloom. Audio data modulates the emission multiplier and slightly shifts the color palette towards red/gold during high bass peaks.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Aetheric Tachyon Lattice
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

// ... (full skeleton with comments)
```

Parameters (for UI sliders)

Fold Count (3.0, 1.0, 6.0, 1.0)
Tachyon Speed (2.0, 0.1, 10.0, 0.1)
Lattice Thickness (0.05, 0.01, 0.2, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
