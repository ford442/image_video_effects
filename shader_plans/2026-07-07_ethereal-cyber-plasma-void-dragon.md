# New Shader Plan: Ethereal Cyber-Plasma Void-Dragon

## Overview
A majestic, hyper-dimensional cyber-dragon forged from flowing quantum plasma and crystalline temporal scales, soaring through a massive, slowly collapsing dark-matter nebula while radiating bioluminescent shockwaves synced to heavy acoustic bass drops.

## Features
- **Hyper-Organic Bioluminescence:** The dragon's internal skeletal structure glows with liquid auroral energy that visibly travels through its circulatory system.
- **Quantum Plasma Breath:** Expels concentrated bursts of fractal dark-matter and luminous plasma that dynamically illuminate the surrounding void.
- **Audio-Reactive Temporal Scales:** Each scale acts as an independent prism, shimmering and physically rippling outward during acoustic peaks.
- **Collapsing Nebula Environment:** A volumetric background composed of dense particle storms and swirling dark-matter clouds that interact with the dragon's movement.
- **Kinematic Serpentine Motion:** The dragon undulates with realistic, fluid mechanics using cascaded sine waves and domain warping.
- **Interactive Gravitational Core:** The dragon fiercely tracks the mouse cursor as a gravitational anchor, twisting its long body to coil around the interaction point.

## Technical Implementation
- File: public/shaders/gen-ethereal-cyber-plasma-void-dragon.wgsl
- Category: generative
- Tags: ["dragon", "plasma", "organic", "quantum", "audio-reactive", "cybernetic", "void"]
- Algorithm: Raymarching an articulated, segmented SDF path driven by stacked noise and sine-wave offsets.

### Core Algorithm
- **Segmented SDF:** Construct the dragon body using a series of smooth-blended capsule SDFs distributed along a 3D spline.
- **Kinematic Displacement:** Apply cascaded 3D Perlin noise and time-driven sine waves to the SDF evaluation position to create fluid, snake-like undulations.
- **Volumetric Nebula:** Utilize heavily layered fractional brownian motion (fBm) in the raymarching accumulation phase to simulate dense, glowing plasma clouds around the dragon.
- **Scale Texturing:** Use voronoi noise and domain repetition over the body surface to carve out intricate, interlocking cyber-scales.

### Mouse Interaction
- The mouse coordinates `u_pointer` drive a target position in 3D space.
- The dragon's head is smoothly interpolated towards the mouse target, with the rest of the body segments following using a delayed kinetic spring model, simulating realistic momentum and weight.

### Color Mapping / Shading
- **Iridescent Metallic:** The outer scales use a complex PBR-style shading with an iridescent reflection map based on viewing angle.
- **Subsurface Glow:** The inner plasma uses a blazing multi-stop gradient (cyan -> hot pink -> pure white) injected via depth-based subsurface scattering.
- **Bloom / Plasma Bleed:** Strong emissive values are applied to the breath and core, causing natural light-bleed in the accumulation buffer.

## Proposed Code Structure (WGSL)
```wgsl
struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// ----------------------------------------------------------------
// Ethereal Cyber-Plasma Void-Dragon
// Category: generative
// ----------------------------------------------------------------

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

// ... (Constants, Noise functions, SDFs, Raymarching logic)

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // Implement raymarching here
}
```
Parameters (for UI sliders)

Name (default, min, max, step)
- Plasma Intensity (1.5, 0.0, 5.0, 0.1)
- Dragon Undulation Speed (1.0, 0.1, 3.0, 0.1)
- Body Segment Density (20.0, 10.0, 40.0, 1.0)
- Nebula Density (0.8, 0.0, 2.0, 0.05)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
