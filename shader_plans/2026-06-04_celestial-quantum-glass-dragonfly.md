# New Shader Plan: Celestial Quantum-Glass Dragonfly

## Overview
A hyper-dimensional, biomechanical dragonfly forged from ethereal quantum-glass and liquid starlight, its intricate fractal wings constantly refracting cosmic energy and beating in synchronous rhythm with ambient audio frequencies inside a volumetric plasma storm.

## Features
- Intricate, multi-layered SDF geometry representing a hyper-detailed dragonfly with articulated joints and crystalline wings.
- Audio-reactive wing kinematics, where acoustic frequencies drive the wing-beat velocity and fractal shatter of the wing membranes.
- Volumetric plasma storm environment featuring swirling aether-fog and floating luminescent pollen.
- Refractive quantum-glass shading that simulates total internal reflection and chromatic dispersion across the fractal surfaces.
- Mouse-interactive gravity vortex, allowing users to bend the flight path and distort the spatial field around the creature.
- Bioluminescent optical pulsing along the neuro-kinetic tail segments, cascading based on rhythmic sonic impulses.

## Technical Implementation
- File: public/shaders/gen-celestial-quantum-glass-dragonfly.wgsl
- Category: generative
- Tags: ["dragonfly", "quantum", "fractal", "audio-reactive", "raymarching", "crystalline"]
- Algorithm: Raymarching complex Signed Distance Fields (SDFs) with KIFS fractal folding for the wings, enveloped in a volumetric raymarched plasma environment.

### Core Algorithm
- Uses a primary raymarching loop to evaluate complex SDF compositions: capped cylinders and smooth-min blends for the thorax and tail, and KIFS (Kaleidoscopic Iterated Function System) fractals for the highly detailed wing venation.
- Simplex noise combined with fractional Brownian motion (fBm) is used to generate the swirling volumetric background fog and atmospheric density.
- Audio data (from `u.config.y`) modulates the rotation matrices of the wings and the amplitude of the fractal distortion.

### Mouse Interaction
- The mouse position (`u.zoom_config.y`, `u.zoom_config.z`) generates a localized spatial deformation well (gravity vortex).
- The space is warped using a smooth distance-based falloff formula: `p -= normalize(p - mouse_pos) * exp(-length(p - mouse_pos) * 2.0) * strength`.
- This causes the dragonfly to appear to orbit or struggle against the gravitational distortion when the mouse is near.

### Color Mapping / Shading
- Quantum-glass material is shaded using a combination of Fresnel approximations, chromatic aberration (sampling different refractive indices for RGB channels), and sharp metallic specular highlights.
- Subsurface scattering is simulated in the tail segments to give a glowing, translucent liquid-plasma look.
- A multi-stop color palette interpolating between deep void blues, vivid bioluminescent cyans, and intense plasma magentas.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Celestial Quantum-Glass Dragonfly
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Wing Frequency, y=Fractal Density, z=Refraction Index, w=Glow Intensity
    ripples: array<vec4<f32>, 50>,
};

// --- CORE UTILITIES ---
fn rot2d(a: f32) -> mat2x2<f32> {
    let s = sin(a); let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ... Additional SDFs, noise functions, raymarching logic ...
```

Parameters (for UI sliders)

Wing Frequency (1.5, 0.1, 5.0, 0.1)
Fractal Density (3.0, 1.0, 8.0, 0.1)
Refraction Index (1.45, 1.0, 3.0, 0.01)
Glow Intensity (2.0, 0.0, 5.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
