# New Shader Plan: Bioluminescent Aether-Jellyfish Pulsar

## Overview
A cosmic entity resembling a massive, translucent jellyfish floating in a quantum aether, pulsing with radiant energy that syncs to an unseen interstellar rhythm. It combines the organic flow of deep-sea life with hyper-futuristic cosmic energy dynamics.

## Features
- Infinite, undulating volumetric aether-jellyfish structures using dynamic 3D SDFs.
- Iridescent, bioluminescent bell and trailing energy tentacles.
- Pulsating inner core that expands and contracts, driving the illumination of the surrounding fluid space.
- Flowing, particle-like sub-surface scattering giving a sense of fluid density and scale.
- Mouse interaction creates localized spatial warping and repels the tentacles like a magnetic field.

## Technical Implementation
- File: public/shaders/gen-bioluminescent-aether-jellyfish-pulsar.wgsl
- Category: generative
- Tags: ["organic", "cosmic", "volumetric", "raymarching", "bioluminescent"]
- Algorithm: Raymarching a complex, organic SDF (combining smooth-blended spheres and custom tentacle functions) in a domain-warped space driven by time and fractional Brownian motion, illuminated by volumetric ray-marching and deep sub-surface scattering.

### Core Algorithm
The primary geometry is created via a smooth minimum (`smin`) blend between a dome-like "bell" shape (modified sphere) and a series of trailing, noise-displaced cylinders (tentacles). The entire scene is domain-warped using 3D fBM noise to give the impression of underwater/cosmic fluid currents. A central pulsating light source acts as the core, using the `u.config.x` time uniform to drive a sine wave expansion and contraction.

### Mouse Interaction
The mouse position (`u.zoom_config.yz`) dictates the center of a strong repulsive force. As the mouse moves, the coordinate space within a certain radius is warped away from the cursor, effectively bending the jellyfish tentacles and fluid around the interaction point. The effect intensifies when the mouse is pressed (`u.zoom_config.w > 0.5`).

### Color Mapping / Shading
Deep volumetric scattering forms the base, transitioning from dark abyssal blues to vibrant cyan and electric violet near the tentacles. The core emits a bright, warm amber/magenta glow. The surface of the jellyfish uses an iridescent mapping that shifts color based on the viewing angle (dot product of normal and view direction).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Bioluminescent Aether-Jellyfish Pulsar
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ----------------------------------------------------------------

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

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Basic 3D Noise for fluid motion
fn hash3(p: vec3<f32>) -> f32 {
    var p2 = fract(p * vec3<f32>(17.1, 31.7, 47.9));
    p2 += dot(p2, p2.yxz + 19.19);
    return fract((p2.x + p2.y) * p2.z);
}

fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), hash3(i + vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), hash3(i + vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
        mix(mix(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), hash3(i + vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), hash3(i + vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

// Scene SDF
fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;
    let t = u.config.x * u.zoom_params.y; // Speed param

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    // Map mouse from 0..1 to -1..1 and adjust aspect ratio (assuming 1.0 for simplicity here, handle properly in main)
    let m_pos = vec3<f32>((mouse.x - 0.5) * 2.0, -(mouse.y - 0.5) * 2.0, 0.0);
    let d_mouse = length(p - m_pos);
    let repel = exp(-d_mouse * 2.0) * u.zoom_params.w; // Repulsion strength param
    p += normalize(p - m_pos) * repel * mix(1.0, 2.0, u.zoom_config.w); // stronger on click

    // Global fluid domain warp
    p += vec3<f32>(noise(p * 2.0 + t), noise(p * 2.1 - t * 0.8), noise(p * 1.9 + t * 1.2)) * 0.5 * u.zoom_params.z;

    // Jellyfish Bell
    let bell_center = vec3<f32>(0.0, 1.0 + sin(t * 2.0)*0.2, 0.0);
    let dbell = length(p - bell_center) - 1.2;
    // Hollow out the bell
    let inside_bell = length(p - bell_center - vec3<f32>(0.0, -0.2, 0.0)) - 1.1;
    let final_bell = max(dbell, -inside_bell);

    // Tentacles
    let num_tentacles = 6.0;
    var dtentacles = 100.0;
    for(var i: f32 = 0.0; i < num_tentacles; i += 1.0) {
        let angle = i * 6.28318 / num_tentacles + t * 0.5;
        let pos = bell_center + vec3<f32>(cos(angle)*0.8, -1.0, sin(angle)*0.8);

        // Tentacle winding
        var tp = p - pos;
        tp.x += sin(tp.y * 3.0 - t * 4.0) * 0.3;
        tp.z += cos(tp.y * 2.5 - t * 3.5) * 0.3;

        let d = length(tp.xz) - 0.05 * (1.0 - smoothstep(-5.0, 0.0, tp.y));
        dtentacles = smin(dtentacles, d, 0.5);
    }

    return smin(final_bell, dtentacles, 0.8);
}

// Normal Calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.01, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }

    let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
    var uv = (fragCoord - 0.5 * resolution) / resolution.y;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, 5.0 + u.zoom_params.x * 5.0); // Zoom param
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));
    let rd = normalize(uv.x * cu + uv.y * cv + 1.5 * cw);

    // Raymarching
    var t = 0.0;
    var max_d = 20.0;
    var col = vec3<f32>(0.0);
    var glow = 0.0;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);

        // Volumetric glow accumulation
        glow += 0.01 / (0.1 + abs(d));

        if (d < 0.001 || t > max_d) { break; }
        t += d;
    }

    if (t < max_d) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(sin(u.config.x), 1.0, cos(u.config.x)));
        let diff = max(dot(n, lightDir), 0.0);

        // Iridescence
        let viewDir = normalize(ro - p);
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);
        let iri = 0.5 + 0.5 * cos(u.config.x * 2.0 + p.y + vec3<f32>(0.0, 2.0, 4.0));

        col = mix(vec3<f32>(0.1, 0.4, 0.8), iri, fresnel) * diff;
    }

    // Add volumetric core glow
    col += vec3<f32>(0.8, 0.2, 0.6) * glow * 0.1 * (0.5 + 0.5*sin(u.config.x * 5.0));

    // Background fade
    col = mix(col, vec3<f32>(0.0, 0.05, 0.1), smoothstep(0.0, max_d, t));

    // Tonemapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)
- Zoom (1.0, 0.0, 2.0, 0.01) - Maps to u.zoom_params.x
- Flow Speed (1.0, 0.0, 3.0, 0.01) - Maps to u.zoom_params.y
- Deformation (1.0, 0.0, 2.0, 0.01) - Maps to u.zoom_params.z
- Repulsion Strength (1.0, 0.0, 3.0, 0.01) - Maps to u.zoom_params.w

Integration Steps
1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
