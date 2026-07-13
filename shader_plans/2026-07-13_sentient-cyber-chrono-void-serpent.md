# New Shader Plan: Sentient Cyber-Chrono Void-Serpent

## Overview
A hyper-dimensional, endlessly twisting biomechanical serpent forged from shattered chrono-glass and liquid auroral plasma, slithering aggressively through a violently decaying temporal cosmic-rift. This shader blends razor-sharp synthetic scales and recursive geometric fracturing with fluid, audio-reactive bioluminescent shockwaves.

## Features
- **Hyper-Organic Cyber-Scales:** A dense network of interlocking geometric scales that shift and reassemble based on temporal noise arrays.
- **Volumetric Temporal Rifts:** Deep space background generated via multi-layered fractional Brownian motion (fBm) and quantum particle distortions.
- **Audio-Reactive Plasma Spine:** A glowing core of liquid aurora that intensifies and expands outwards during heavy acoustic bass drops.
- **Fractal Time-Echoes:** Ghostly, chromatic after-images of the serpent that lag behind its movement, creating a sense of broken time.
- **Gravitational Mouse Distortion:** Interactive mouse tracking that acts as a local gravitational singularity, bending the serpent's body and the surrounding temporal rift towards the cursor.

## Technical Implementation
- File: public/shaders/gen-sentient-cyber-chrono-void-serpent.wgsl
- Category: generative
- Tags: ["organic", "cybernetic", "fractal", "volumetric", "audio-reactive"]
- Algorithm: Raymarching combined with domain repetition, fractal space-folding, and volumetric scattering.

### Core Algorithm
The central structure relies on a curved SDF path mapped through a warped coordinate system, allowing the serpent to twist endlessly. The body is detailed using a Voronoi-based displacement map to simulate biomechanical scales. The surrounding void utilizes 3D value noise and domain repetition to scatter quantum star fields and auroral dust, creating depth.

### Mouse Interaction
Mouse coordinates `let mouse = u.zoom_config.yz;` generate a localized distortion field. In the mapping function: `map(p - vec3<f32>(mouse.x * 3.0, mouse.y * 3.0, 0.0), ...)`. The field applies a smooth polynomial minimum (smin) pull on the serpent's path, effectively warping the spatial coordinates towards the pointer like a gravity well.

### Color Mapping / Shading
A vivid chromatic dispersion technique using phase-shifted cosines produces the liquid-aurora effect (cyan, deep purple, and neon gold). The biomechanical scales employ a metallic shading model with high specular highlights and a dark, obsidian base, offset by the intense subsurface scattering of the plasma spine.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Sentient Cyber-Chrono Void-Serpent
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};
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

const PI: f32 = 3.14159265359;

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 2D Hash
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

// Map function for the raymarching
fn map(p: vec3<f32>) -> f32 {
    let mouse = u.zoom_config.yz;
    let dist = length(p.xy - mouse * 3.0);
    // ... serpent logic ...
    return length(p) - 1.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // ... rendering logic ...
}
```

Parameters (for UI sliders)

Time Scale (1.0, 0.0, 5.0, 0.1)
Plasma Intensity (1.0, 0.0, 3.0, 0.1)
Void Density (0.5, 0.0, 1.0, 0.05)
Fracture Depth (2.0, 0.0, 10.0, 0.5)
