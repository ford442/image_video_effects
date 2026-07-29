# New Shader Plan: Chronos Biomechanical Void-Leviathan

## Overview
A colossal, ancient biomechanical leviathan forged from shifting quantum-obsidian and echoing temporal-glass, swimming gracefully through a violently fractured space-time nebula while continuously shedding liquid auroral starlight.

## Features
- **Biomechanical Leviathan Anatomy:** An intricate blend of rigid cybernetic plating, deep-void obsidian scales, and exposed pulsating fluid cores mimicking organic life.
- **Temporal Fractal Wake:** As the leviathan moves, it disrupts the fabric of the void, leaving behind a fading trail of recursive geometric time-fractures (KIFS).
- **Acoustic Symbiosis:** Giant bioluminescent ribbed sections running along its flanks react violently to sub-bass acoustic frequencies, violently flashing neon-cyan and deep magenta.
- **Volumetric Space-Time Nebula:** A dense, layered raymarched background formed from 3D flow-noise, creating the illusion of deep, crushing cosmic oceanic pressure.
- **Liquid Auroral Shedding:** Thousands of microscopic glowing particle-streams cascading off the leviathan's fins, mimicking a constant decay of radioactive quantum energy.

## Technical Implementation
- File: public/shaders/gen-chronos-biomechanical-void-leviathan.wgsl
- Category: generative
- Tags: ["leviathan", "biomechanical", "void", "quantum", "audio-reactive", "temporal", "volumetric"]
- Algorithm: Volumetric raymarching integrating smooth-min for the organic cyborg body structure, coupled with domain repetition for the ribcage/scales, and multi-octave 3D value noise for the crushing void atmosphere.

### Core Algorithm
- **SDF Construction:** The leviathan is built using a series of elongated capsule and ellipsoid SDFs smoothly blended (smin). A sine wave domain distortion across the Z-axis provides the graceful swimming motion based on `u.config.x` (Time).
- **Scale/Plating Detailing:** High-frequency modulo arithmetic on the SDF coordinates generates the repeating cybernetic plating and glowing acoustic ribbing.
- **Nebula Background:** A secondary, highly stepped raymarching loop calculates the volumetric density using 3D fractional Brownian motion (fBm) to render the cloudy, deep-void oceanic environment.

### Mouse Interaction
- The leviathan naturally swims forward. Dragging the mouse applies a rotational matrix to the global coordinate space, allowing the user to seamlessly orbit and inspect the leviathan from all angles, while extreme mouse deltas induce temporary visual glitch/chromatic aberration on the temporal wake.

### Color Mapping / Shading
- **Subsurface Plasma:** Deep, rich subsurface scattering approximations for the bioluminescent fluid, transitioning from hot magenta cores to radioactive cyan edges.
- **Obsidian Plating:** Highly specular, dark metallic reflections on the cybernetic armor using calculated normals.
- **Atmospheric Depth:** Heavy volumetric fog fading to pitch black based on the ray distance to simulate the crushing darkness of the cosmic ocean.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Chronos Biomechanical Void-Leviathan
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var<storage, read_write> touchBuffer: array<TouchData>;
@group(0) @binding(5) var<storage, read_write> infoBuffer: array<InfoData>;
@group(0) @binding(6) var<storage, read_write> plasmaBuffer: array<PlasmaData>;
@group(0) @binding(7) var non_filtering_sampler: sampler;
@group(0) @binding(8) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(9) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<ExtraData>;

// --- GLOBALS & UNIFORMS ---
// ... (Standard Uniform structs)

// --- SDF FUNCTIONS ---
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    // ...
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    // ...
}

// --- DOMAIN WARPING ---
fn swimDistortion(p: vec3<f32>, time: f32) -> vec3<f32> {
    // ...
}

// --- MAP SCENE ---
fn map(p: vec3<f32>) -> f32 {
    // 1. Apply swim distortion
    // 2. Build leviathan SDF
    // 3. Add cyber-plating details
    // 4. Return combined distance
}

// --- RAYMARCHING ---
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> f32 {
    // ...
}

// --- LIGHTING & COLOR ---
fn getNormal(p: vec3<f32>) -> vec3<f32> {
    // ...
}
fn shade(p: vec3<f32>, normal: vec3<f32>, rayDir: vec3<f32>) -> vec3<f32> {
    // ...
}

// --- COMPUTE SHADER ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) GlobalInvocationID: vec3<u32>) {
    // 1. Coordinates setup
    // 2. Camera & Ray Direction setup (orbit via touchBuffer)
    // 3. Audio Reactivity setup (plasmaBuffer)
    // 4. Raymarch Scene
    // 5. Volumetric background pass
    // 6. Output Color
}
```

## Parameters (for UI sliders)
- `u.config.x`: Time (Default: mapped to global time, controls swimming motion and nebula drift)
- `u.config.y`: Audio Reactivity Multiplier (Default: 1.0, Min: 0.0, Max: 2.0, Step: 0.05) - Intensifies the pulsing glow of the cyber-ribbing.
- `u.config.z`: Brightness / Aurora Intensity (Default: 1.0, Min: 0.5, Max: 3.0, Step: 0.1) - Controls the emissive strength of the leviathan's liquid starlight shedding.
- `u.config.w`: Evolution Speed Multiplier (Default: 1.0, Min: 0.1, Max: 5.0, Step: 0.1) - Controls how fast the temporal fractals decay in the wake.
