# New Shader Plan: Ethereal Cyber-Chrono Nebula-Phoenix

## Overview
A majestic, hyper-organic cybernetic phoenix rising from a deep-space nebula, its wings woven from liquid auroral plasma and shattered quantum glass that burst into geometric temporal fractals upon acoustic climax.

## Features
- Volumetric deep-space nebula with swirling quantum-plasma currents
- Biomechanical phoenix composed of intricate, glowing cyber-skeletal ribs and prismatic quantum glass
- Audio-reactive temporal-feedback wings that ripple and expand with cosmic bass drops
- Gravitational singularity core that heavily distorts the surrounding chrono-fabric
- Temporal chromatic aberration that shifts based on audio frequency and mouse proximity
- Infinite fractal nesting within the phoenix's plumage using recursive SDFs
- ACES tone mapping combined with upgraded RGBA handling for hyper-vibrant plasma glow

## Technical Implementation
- File: public/shaders/gen-ethereal-cyber-chrono-nebula-phoenix.wgsl
- Category: generative
- Tags: ["phoenix", "cybernetic", "quantum", "nebula", "chrono", "audio-reactive"]
- Algorithm: Raymarching a complex composition of recursive SDFs for the phoenix, blended with volumetric noise for the nebula, and warped by temporal domain distortion for the chrono-fabric.

### Core Algorithm
The scene is built via raymarching. The primary SDF is a combination of smooth-blended geometric shapes (capsules and tori) for the cyber-skeletal structure, interwoven with 3D fractal noise to form the plumage. Domain repetition and recursive folding (similar to KIFS) generate the intricate feather structures. The volumetric nebula is evaluated using multi-octave 3D simplex noise with density accumulation along the ray.

### Mouse Interaction
The mouse position acts as a gravitational singularity (black hole).
- Formula: `p = p + normalize(p - mousePos) * (gravityWellStrength / length(p - mousePos))`
- Behavior: The phoenix and the nebula are pulled toward the mouse, warping the space and increasing temporal feedback intensity near the cursor.

### Color Mapping / Shading
- Subsurface scattering simulation for the quantum glass feathers using a thickness approximation.
- Dual-tone gradient mapping for the auroral plasma (cyan/magenta shifting based on time and audio).
- Intense bloom pass (simulated via high accumulation of glowing SDFs) on the core and wingtips.
- Shading incorporates an iridescent fresnel effect on the cybernetic components, finished with an ACES tone mapping curve for cinematic contrast.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Ethereal Cyber-Chrono Nebula-Phoenix
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
    zoom_params: vec4<f32>,  // x=Shatter Threshold, y=Chime Density, z=Refraction Index, w=Transmission
    ripples: array<vec4<f32>, 50>,
};

// --- CORE UTILITIES ---
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// --- SDF FUNCTIONS ---
fn sdPhoenix(p: vec3<f32>) -> f32 {
    // Recursive structure for the phoenix
    var q = p;
    // ... logic ...
    return length(q) - 1.0;
}

// --- MAIN RENDERING ---
@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dim = textureDimensions(writeTexture);
    if (id.x >= dim.x || id.y >= dim.y) { return; }

    // ... rendering loop ...

    // Output
    textureStore(writeTexture, id.xy, vec4<f32>(vec3<f32>(1.0), 1.0));
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Plasma Intensity (1.0, 0.0, 5.0, 0.1)
- Fractal Recursion (3.0, 1.0, 7.0, 1.0)
- Gravity Well Strength (0.5, 0.0, 2.0, 0.05)
- Audio Reactivity (1.0, 0.0, 3.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
