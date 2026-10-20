# New Shader Plan: Bioluminescent Neural-Coral Matrix

## Overview
A mesmerizing descent into a deep-sea techno-reef where organic coral structures pulse with the rhythm of a synthetic neural network.

## Features
- Intricate, branching SDF structures mimicking brain coral and neural dendrites.
- Pulsing bioluminescent energy streams that flow through the coral veins.
- Subsurface scattering effects for a fleshy, translucent organic appearance.
- Audio-reactive growth and illumination driven by low-frequency bass and mid-tones.
- Fluid-like spatial distortion simulating deep underwater currents.
- Mouse-driven gravity wells that attract and bend the neural tendrils.
- High-contrast color palette of deep cyan, electric pink, and bio-green against a pitch-black abyss.

## Technical Implementation
- File: public/shaders/gen-bioluminescent-neural-coral-matrix.wgsl
- Category: generative
- Tags: ["organic", "neural", "coral", "bioluminescence", "cybernetic", "sdf", "audio-reactive"]
- Algorithm: Raymarching through domain-warped 3D cellular noise and branching gyroid SDFs.

### Core Algorithm
The environment is built using a primary Raymarching loop over a complex SDF. The base structure is a highly distorted gyroid (using `sin` and `cos` spatial folds) combined with fBM (Fractional Brownian Motion) applied to the spatial coordinates before evaluating the SDF to simulate gentle underwater currents and organic irregularity. Audio reactivity (`plasmaBuffer[0]`) modulates the extrusion thickness and the emission intensity of the network pathways.

### Mouse Interaction
When `u.zoom_config.w > 0.5` (mouse down), the raymarching coordinates are distorted around the `u.zoom_config.yz` (mouse UV) position. This creates a localized "gravity well" that pulls the coral structures and light streams toward the cursor using a smooth inverse-square attenuation function, making it feel like a physical interaction with a fluid medium.

### Color Mapping / Shading
The shading model employs a custom Subsurface Scattering (SSS) approximation using multiple SDF taps toward the light source to give the coral a fleshy, semi-translucent look. The valleys of the coral emit bright, glowing colors mapped from the spatial position and time. A post-processing bloom effect is simulated by accumulating emissive values along the ray and blurring the final output texture.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Bioluminescent Neural-Coral Matrix
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
struct Uniforms {
  config: vec4<f32>,              // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,         // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,         // .xyzw = user params p1..p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};
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

// --- Helper Functions ---
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// SDF for the Neural Coral
fn map(pos: vec3<f32>) -> f32 {
    var p = pos;

    // Mouse Interaction: Gravity well
    if (u.zoom_config.w > 0.5) {
        let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (0.5 - u.zoom_config.z) * 5.0, 0.0);
        let dist = length(p - mouse_pos);
        let pull = 1.0 / (1.0 + dist * dist);
        p = p - normalize(p - mouse_pos) * pull * u.zoom_params.y;
    }

    // Audio reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let pulse = sin(u.config.x * 2.0 + p.z * 0.5) * bass;

    // Gyroid structure
    let scale = u.zoom_params.x; // Scale param
    var d = (dot(sin(p * scale), cos(p.zxy * scale)) + 0.5) / scale;

    // Organic fBM distortion
    d += sin(p.x * 3.0 + u.config.x) * 0.1;

    return d - (0.1 + pulse * 0.05); // Thickness based on audio
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var t = 0.0;
    var glow = 0.0;
    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if (d < 0.001) { break; }
        if (t > 20.0) { t = -1.0; break; }
        t += d * 0.5;
        glow += 0.01 / (0.01 + d * d);
    }
    return vec2<f32>(t, glow);
}

// Compute normal
fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) { return; }

    let uv = (vec2<f32>(id.xy) - 0.5 * resolution) / resolution.y;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, u.config.x * u.zoom_params.z); // Move forward over time
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Slight camera roll
    let rxy = rd.xy * rot2D(sin(u.config.x * 0.2) * 0.1);
    rd = vec3<f32>(rxy, rd.z);

    let result = raymarch(ro, rd);
    let t = result.x;
    let glow = result.y;

    var color = vec3<f32>(0.0);
    var out_depth = 1.0;
    var n = vec3<f32>(0.0);

    if (t > 0.0) {
        let p = ro + rd * t;
        n = getNormal(p);

        let lightDir = normalize(vec3<f32>(sin(u.config.x), 1.0, cos(u.config.x)));
        let diff = max(dot(n, lightDir), 0.0);
        let sss = clamp(map(p + lightDir * 0.2) / 0.2, 0.0, 1.0);
        let baseColor = mix(vec3<f32>(0.02, 0.1, 0.15), vec3<f32>(0.1, 0.05, 0.1), clamp(p.y, 0.0, 1.0));

        color = baseColor * (diff * 0.5 + 0.5) * sss;
        let emission = vec3<f32>(0.0, 0.8, 1.0) * glow * u.zoom_params.w;
        color += emission;
        color = mix(color, vec3<f32>(0.0, 0.01, 0.03), 1.0 - exp(-0.05 * t));
        out_depth = t / 20.0;
    } else {
        color = vec3<f32>(0.0, 0.02, 0.05) * glow * 0.1;
    }

    textureStore(writeTexture, id.xy, vec4<f32>(color, 1.0));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(out_depth, out_depth, out_depth, 1.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(n, 1.0));
}
```
Parameters (for UI sliders)

Structure Scale (2.5, 1.0, 5.0, 0.1)
Distortion Intensity (1.5, 0.0, 3.0, 0.1)
Travel Speed (1.0, 0.0, 5.0, 0.1)
Bioluminescence (1.0, 0.0, 3.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
