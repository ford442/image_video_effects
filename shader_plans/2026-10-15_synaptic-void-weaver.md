# New Shader Plan: Synaptic Void-Weaver

## Overview
A biomechanical abyss where luminescent neural tendrils pulse with electric thoughts, weaving through an endless, shifting dark matter fractal.

## Features
- Evolving, branching fractal tendrils mimicking neural pathways.
- Pulsating bioluminescent energy surges flowing along the paths.
- Dark matter gravity wells that distort and warp the surrounding space.
- Audio-reactive electric sparks triggered by treble and bass spikes.
- A slowly shifting, abyssal background with subtle liquid-metal reflections.
- Mouse interaction creates temporary localized "thought-nodes" that attract the tendrils.

## Technical Implementation
- File: public/shaders/gen-synaptic-void-weaver.wgsl
- Category: generative
- Tags: ["organic", "neural", "dark-matter", "bioluminescent", "fractal", "interactive"]
- Algorithm: Raymarching through domain-warped 3D noise combined with a web-like SDF network, perturbed by audio reactivity and mouse gravity wells.

### Core Algorithm
The environment is defined by a 3D raymarching function. A base volumetric structure uses smooth-min (`smin`) blended cylinder SDFs representing the neural tendrils. Space is folded using a 3D rotation and absolute-value operations (a modified Menger-like fractal process mixed with gyroid noise) to create infinite branching. The domain is perturbed by low-frequency 3D noise to give an organic, shifting feel over time. Audio reactivity (`plasmaBuffer[0]`) scales the tendril thickness (bass) and injects sharp emissive pulses (treble) along the UV coordinates.

### Mouse Interaction
The mouse acts as an intense gravity well. If `u.zoom_config.w > 0.5`, the raymarching domain (`p`) is spherically warped towards `vec3(mouse_uv * 2.0 - 1.0, 0.0)`. The distortion follows an inverse-square falloff: `p -= normalize(p - mouse_pos) * (strength / (dist * dist + 0.1))`. This causes the neural tendrils to physically bend and cluster around the cursor.

### Color Mapping / Shading
The tendrils have a base dark, obsidian-like color with high specularity (calculated via standard SDF normals). An emissive layer is added based on the fractal iteration count and time, producing bright cyan and magenta bioluminescence. The background features a subtle, deep purple glow. A post-processing bloom effect is approximated by accumulating steps during the raymarch and adding it to the final color.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Synaptic Void-Weaver
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

// ... (full skeleton with comments)

// Helper: 3D Rotation Matrix
fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let s = sin(angle);
    let c = cos(angle);
    let oc = 1.0 - c;
    return mat3x3<f32>(
        oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
        oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
        oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c
    );
}

// Helper: Smooth Min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Map function (SDF)
fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;

    // Mouse Interaction (Gravity Well)
    if (u.zoom_config.w > 0.5) {
        let mouse_pos = vec3<f32>(u.zoom_config.y * 2.0 - 1.0, u.zoom_config.z * 2.0 - 1.0, 0.0);
        let dist = length(p - mouse_pos);
        p -= normalize(p - mouse_pos) * (0.5 / (dist * dist + 0.1));
    }

    // Audio Reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);

    // Domain Warping / Fractal
    var d = 100.0;
    for(var i = 0; i < 4; i++) {
        p = abs(p) - 1.0;
        p = p * rot3D(normalize(vec3<f32>(1.0, 1.0, 1.0)), u.config.x * 0.1);

        let tube = length(p.xy) - 0.1 - (bass * 0.05);
        d = smin(d, tube, 0.5);
    }

    return vec2<f32>(d, 1.0); // Return distance and material ID
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // ... setup rays, raymarching loop, shading, and write to textures
}
```
Parameters (for UI sliders)

Glow Intensity (1.5, 0.0, 5.0, 0.1)
Fractal Iterations (4.0, 1.0, 8.0, 1.0)
Tendril Thickness (0.1, 0.01, 0.5, 0.01)
Rotation Speed (0.1, 0.0, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
