# New Shader Plan: Prismatic Cyber-Aurora Astral-Dragonfly

## Overview
A majestic, hyper-organic biomechanical dragonfly forged from liquid auroral plasma and shattered chromatic crystal, violently beating its iridescent four-fold wings while traversing a chaotic quantum-storm void, intensely reacting to cascading acoustic frequencies.

## Features
- **Volumetric Auroral Wings:** Shifting, iridescent plasma fields that mimic the intricate network of a dragonfly's wings, expanding and shattering in rhythm with high-end acoustic frequencies.
- **Biomechanical Liquid-Crystal Body:** A segmented, metallic abdomen composed of refractive dark-matter and luminous neon circuitry that bends ambient starlight.
- **Sonic Wing Beats:** The wing flapping speed and physical expansion directly map to the intensity of the audio input, creating explosive bursts of kinetic energy.
- **Quantum-Storm Voids:** The background is a dense, swirling nebula of chaotic dark matter and scattered, glowing aether-particles that repel from the dragonfly's path.
- **Chromatic Temporal-Ripples:** Complex iridescent refractions spread outwards from the wings into the surrounding void as shockwaves of shattered time.

## Technical Implementation
- File: public/shaders/gen-prismatic-cyber-aurora-astral-dragonfly.wgsl
- Category: generative
- Tags: ["organic", "quantum", "cybernetic", "aurora", "particle-systems", "cosmic"]
- Algorithm: Raymarching combined with domain repetition, smooth-minimum organic modeling, and complex 3D noise for volumetric rendering.

### Core Algorithm
The core architecture utilizes Raymarching to model the dragonfly's intricate form. The body uses rounded capsules and segmented tori blended using a smooth minimum function (`smin`) to achieve a cohesive, biomechanical look. The wings are heavily distorted intersecting planes layered with fractional Brownian motion (fBm) noise to simulate translucent, complex crystalline membranes. Ambient deep-space nebula is simulated using a separate low-density volumetric integration step over cellular 3D noise for the quantum storm.

### Mouse Interaction
The user's mouse position maps to a local gravity well near the dragonfly. By dragging the mouse, the user can bend the spatial domain around the dragonfly, causing the tail segments to curl toward the gravity point while generating localized iridescent chromatic aberrations in the rendering field.

### Color Mapping / Shading
Shading employs an iridescent physically-based lighting approximation. The dragonfly's exoskeleton mixes deep obsidian and reflective chrome, overlaid with dynamic liquid-neon emissive textures. The wings use a view-dependent transmission approximation, shifting between brilliant cyan, magenta, and gold depending on the viewing angle and wing velocity. A global volumetric glow map creates dramatic blooming across the scene.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Prismatic Cyber-Aurora Astral-Dragonfly
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Shatter Threshold, y=Chime Density, z=Refraction Index, w=Transmission
    ripples: array<vec4<f32>, 50>,
};

// --- CORE UTILS ---
// (rotations, smin, noise, hash)

// --- SDF SCENE ---
// fn map(p: vec3<f32>) -> vec2<f32> {
//     // Dragonfly Body (segments + smin)
//     // Dragonfly Wings (intersecting distorted planes + fBm)
// }

// --- LIGHTING & VOLUMETRICS ---
// fn render(ro, rd) -> vec4<f32> {
//     // raymarch scene
//     // view-dependent iridescent shading
//     // volumetric background nebula accumulation
// }

// --- MAIN COMPUTE ---
@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // resolution setup
    // ray origin, ray direction calculation
    // mouse interaction domain distortion
    // write output to writeTexture
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Wing Distortion (0.5, 0.0, 1.0, 0.01)
- Quantum Turbulence (0.2, 0.0, 1.0, 0.01)
- Iridescence Shift (0.0, -1.0, 1.0, 0.01)
- Nebula Density (0.4, 0.0, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
