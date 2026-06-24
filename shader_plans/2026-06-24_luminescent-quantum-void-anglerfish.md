# New Shader Plan: Luminescent Quantum-Void Anglerfish

## Overview
A colossal, biomechanical deep-space anglerfish silently prowling through an ocean of swirling dark-matter, utilizing a miniature, violently pulsating quantum star as its bioluminescent lure to attract fragmented aether-particles.

## Features
- Majestic Cyber-Organic Exoskeleton: The anglerfish features intricate, interlocking brass-like fractal gears and ribbed armor plates that rotate seamlessly.
- Miniaturized Quantum-Star Lure: The dangling esca is a hyper-dense, aggressively pulsating core of plasma that reacts violently to acoustic drops.
- Volumetric Dark-Matter Ocean: The environment is a computationally intensive, thick volumetric fluid that heavily distorts light via pseudo-refraction.
- Aether-Particle Swarm: Tiny, glowing geometric motes swarm uncontrollably around the star lure, simulating complex gravitational attraction.
- Translucent Bioluminescent Fins: Ethereal fins woven from flowing liquid-neon energy that ripple and tear at the fabric of space-time.

## Technical Implementation
- File: public/shaders/gen-luminescent-quantum-void-anglerfish.wgsl
- Category: generative
- Tags: ["cosmic", "anglerfish", "quantum", "mechanical", "organic", "audio-reactive", "volumetric"]
- Algorithm: Complex SDF raymarching integrating smooth-min organic shapes with hard-edge fractal domains, paired with a volumetric absorption/emission pass for the deep-void water.

### Core Algorithm
- The anglerfish body utilizes deformed spheres and capsules merged via `smin`, layered with high-frequency noise displacement for a pitted, ancient texture.
- The teeth and mechanical jaw pieces use repeated box and cone SDFs mapped along curved domains.
- The quantum-star lure employs a highly emissive sphere combined with a turbulent 3D noise field for the plasma corona.
- Volumetric rendering accumulates density along the ray, applying an exponential decay (Beer's Law) tinted with deep midnight blues and violet.

### Mouse Interaction
- Moving the mouse dictates the position of an external gravitational anomaly, causing the anglerfish to slowly turn its massive body and gaze toward the cursor.
- Clicking emits a sonic shockwave through the dark-matter ocean, temporarily blowing the aether-particle swarm away from the lure before they rush back in.

### Color Mapping / Shading
- The mechanical shell leverages physically-based shading with high specular highlights and a dark, tarnished metallic base.
- The lure and particle swarm are pure emissive HDR values, blooming into cyan and magenta tones mapped directly to `u.zoom_params` (audio).
- The volumetric background uses gradient-mapped domain warping to create the illusion of thick, churning cosmic liquid.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Luminescent Quantum-Void Anglerfish
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
// Jaw Rotation (0.5, 0.0, 1.0, 0.01)
// Lure Intensity (1.0, 0.5, 5.0, 0.1)
// Void Density (0.8, 0.1, 2.0, 0.05)
// Fractal Rust (0.5, 0.0, 1.0, 0.05)

// ----------------------------------------------------------------
// Integration Steps
// ----------------------------------------------------------------
// Create shader file
// Create JSON definition
// Run generate_shader_lists.js
// Upload via storage_manager
```
