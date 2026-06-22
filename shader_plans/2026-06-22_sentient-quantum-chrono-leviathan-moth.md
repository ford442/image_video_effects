# New Shader Plan: Sentient Quantum-Chrono Leviathan-Moth

## Overview
A majestic, colossal cybernetic space moth floating through a deep-space nebula, its wings woven from crystalline threads of frozen time and quantum aether-plasma that softly pulse and ripple in sync with ambient cosmic acoustics.

## Features
- Colossal Cybernetic Moth Structure: Intricate, biomechanical exoskeleton constructed using organic-looking fractal geometries and SDF shapes.
- Temporal-Crystal Wings: The wings are formed from semi-transparent, refractive crystalline threads that visually distort space behind them.
- Quantum Aether-Plasma Dust: The moth continuously sheds glowing, bioluminescent plasma particles (dust) from its wings that swirl into an ethereal trail.
- Acoustic Chrono-Resonance: Bass drops and audio frequency spikes cause the crystal wings to physically ripple and temporally distort the surrounding space.
- Volumetric Cosmic Void: The entity floats within an endlessly deep, foggy volumetric cosmic nebula colored by neon bio-fluorescence.

## Technical Implementation
- File: public/shaders/gen-sentient-quantum-chrono-leviathan-moth.wgsl
- Category: generative
- Tags: ["cosmic", "moth", "quantum", "crystal", "organic", "mechanical", "audio-reactive"]
- Algorithm: Advanced raymarching of complex SDFs with domain folding and volumetric density accumulation for nebula and plasma trails.

### Core Algorithm
- Utilizes an advanced gyroid-based volumetric raymarcher to generate the cosmic nebula background.
- The moth's main body uses elongated capsule SDFs merged with smooth minimums and fractal displacement (fractional Brownian motion) to create a bio-mechanical exoskeleton.
- The wings are generated via symmetrically folded, thin flat SDFs with 3D Voronoi noise mapped over the surface to create the crystalline web structure.
- Particle trails (dust) are simulated procedurally by evaluating fractal noise along the trailing axis, creating a continuous glowing flow without actual particle state.

### Mouse Interaction
- The mouse acts as a gravitational chronal anomaly. Orbiting the mouse around the screen applies a 3D rotation matrix to the entire moth entity, while mouse click/drag accelerates the shedding of quantum dust and intensifies the wing's glowing aether-plasma.

### Color Mapping / Shading
- Employs a complex physically-inspired shading model: the exoskeleton is highly metallic and reflective, bouncing the nebula's ambient light.
- The crystalline wings use a faux-refraction approach by distorting the background raymarch coordinates based on the wing's surface normal.
- Glowing plasma dust uses additive blending and Blackbody radiation color mapping (shifting from deep bioluminescent cyan to bright neon pink at high intensities).
- A final ACES filmic tonemapping curve ensures vibrant colors and prevents blowouts from the additive glowing dust.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Sentient Quantum-Chrono Leviathan-Moth
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Wing Span, y=Plasma Intensity, z=Chrono Distortion, w=Nebular Density
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

// ----------------------------------------------------------------
// Helper functions and Math utilities
// ----------------------------------------------------------------
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// ----------------------------------------------------------------
// Main Compute
// ----------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dim = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(id.xy) / dim;

    // ... Raymarching and shading implementation ...

    textureStore(writeTexture, id.xy, vec4<f32>(uv.x, uv.y, 0.5, 1.0));
}
```

## Parameters (for UI sliders)

Name (default, min, max, step)
- Wing Span (1.5, 0.5, 3.0, 0.1)
- Plasma Intensity (2.0, 0.1, 5.0, 0.1)
- Chrono Distortion (0.5, 0.0, 1.0, 0.05)
- Nebular Density (0.8, 0.1, 2.0, 0.1)

## Integration Steps

1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
