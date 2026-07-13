# New Shader Plan: Luminescent Quantum-Void Astral-Turtle

## Overview
A hyper-organic, glowing biomechanical space-turtle drifting through a volumetric quantum nebula, its shell woven from shattered chromatic crystal and liquid-plasma that intensely reacts to deep bass frequencies.

## Features
- Volumetric quantum nebula background with audio-reactive swirling aether
- Biomechanical space-turtle with a shell constructed of fractal, glowing chromatic glass
- Dynamic audio-reactive plasma currents flowing between the shell's crystalline segments
- Temporal rippling effects applied to the turtle's fins, mimicking fluid acoustic waves
- Pulsating quantum core visible through the translucent bio-shell
- Mouse-driven gravity wells that bend the plasma streams around the turtle
- Chromatic aberration and deep glowing bloom effects for a cinematic cosmic feel

## Technical Implementation
- File: public/shaders/gen-luminescent-quantum-void-astral-turtle.wgsl
- Category: generative
- Tags: ["organic", "quantum", "cosmic", "animal", "volumetric"]
- Algorithm: Raymarching through a volumetric SDF combined with 3D noise and domain warping to generate the turtle's shell and plasma environment.

### Core Algorithm
The scene uses raymarching against a complex SDF composed of a central modified sphere (the shell) and elongated, smooth-blended appendages (fins and head). The shell's surface is perturbed using fractal Brownian motion (fBm) 3D noise to create shattered, crystal-like facets. A dense volumetric raymarching pass adds the glowing quantum nebula in the background, utilizing domain repetition for distant stars.

### Mouse Interaction
The mouse cursor acts as a localized gravitational anomaly. As the mouse moves across the screen (via `u.zoom_config.y` and `u.zoom_config.z`), it introduces an orbital distortion formula (e.g., `p.xz *= rot2D(mouse_dist * 5.0)`) that twists the surrounding plasma streams and slightly bends the ray trajectories around the turtle, enhancing the perception of a dense quantum void.

### Color Mapping / Shading
The turtle's shell utilizes an iridescent subsurface scattering approximation, shifting from deep cosmic purples and bioluminescent cyan to bright quantum pink at audio peaks (`u.config.y`). The surrounding plasma features a highly emissive glowing metallic shade. Bloom is simulated through accumulating emissive color along the raymarching steps, resulting in a deep, radiant glow.

## Proposed Code Structure (WGSL)
```wgsl
struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// ----------------------------------------------------------------
// Luminescent Quantum-Void Astral-Turtle
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

// PRNG
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// 3D Noise and SDFs
// ... (full skeleton with comments)

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let size = textureDimensions(writeTexture);
    if (id.x >= size.x || id.y >= size.y) { return; }

    // Shader logic
}
```

Parameters (for UI sliders)

Fractal Detail (3.0, 1.0, 5.0, 0.1)
Plasma Glow (1.5, 0.0, 3.0, 0.1)
Void Density (0.8, 0.1, 2.0, 0.05)
Acoustic Reactivity (1.0, 0.0, 2.0, 0.1)