# New Shader Plan: Luminescent Quantum-Void Astro-Tiger

## Overview
A hyper-majestic, cybernetic space-tiger woven from shattered quantum glass and radiant liquid-plasma, bounding through a massive volumetric particle-storm void while its roaring sonic-reactive stripes carve auroral rifts into the aether.

## Features
- Intricate biomechanical tiger silhouette defined by morphing fractal noise and SDF composition.
- Audio-reactive stripes that surge with liquid-aurora plasma in sync with heavy cosmic bass.
- Volumetric quantum-storm void featuring spiraling aether-particles and chrono-distortions.
- Paws that leave fading trails of shattered chromatic crystals within the deep-space nebula.
- Multi-layered parallax environment reacting dynamically to the roaring central entity.

## Technical Implementation
- File: public/shaders/gen-luminescent-quantum-void-astro-tiger.wgsl
- Category: generative
- Tags: ["animal", "tiger", "cybernetic", "quantum", "plasma", "volumetric", "fractal", "audio-reactive"]
- Algorithm: Raymarching combined with domain repetition for the environment, intricate SDFs for the tiger anatomy with fBM (fractional Brownian motion) for the flowing plasma fur, and a volumetric raycaster for the background nebula.

### Core Algorithm
1.  **Raymarching & SDFs**: The tiger's core geometry is formed by blending various geometric SDFs (ellipsoids, capsules) smoothed out to create a cohesive organic shape. The cybernetic armor is sharp and angular.
2.  **Noise & Texturing**: 3D fBM noise is used to displace the surface of the tiger, creating the illusion of flowing, liquid-plasma fur. The stripes are a specific frequency threshold of this noise, modulated heavily by the `u.config.y` (audio) variable.
3.  **Background Void**: A secondary volumetric raymarching pass for a dense, swirling nebula, using chaotic curl noise to drive particle-like density clouds.
4.  **Temporal Distortion**: The `u.config.x` (time) variable drives the leaping animation loop and the slow churn of the surrounding quantum-storm void.

### Mouse Interaction
The mouse (`u.mouse`) creates a localized gravity well, pulling the surrounding aether-particles toward the cursor and slightly distorting the tiger's plasma flow in the direction of the interaction, as if reaching out to the cosmic rift.

### Color Mapping / Shading
The palette heavily contrasts the deep, dark matter void (obsidians, deep purples, abyssal blues) with the intense, blinding luminescence of the tiger (cyan, hyper-magenta, and molten gold). Subsurface scattering approximations give the cyber-glass armor a refractive, crystalline quality, while bloom is implied by high-intensity emissive values on the plasma stripes.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Luminescent Quantum-Void Astro-Tiger
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    mouse: vec4<f32>,
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    ripples: vec4<f32>,
    plasma_intensity: f32,
    quantum_storm_density: f32,
    stripe_resonance: f32,
    void_color_shift: f32,
}
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

// --- SHADER LOGIC ---
const MAX_STEPS = 100;
const SURF_DIST = 0.001;
const MAX_DIST = 100.0;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let time = u.config.x;
    let audio = u.config.y;
    // Implementation details...
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
plasma_intensity (1.0, 0.0, 2.0, 0.01)
quantum_storm_density (0.5, 0.0, 1.0, 0.01)
stripe_resonance (0.8, 0.0, 1.5, 0.01)
void_color_shift (0.0, -1.0, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
