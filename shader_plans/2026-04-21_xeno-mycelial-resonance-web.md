# New Shader Plan: Xeno-Mycelial Resonance-Web

## Overview
An infinite, subterranean expanse of bioluminescent, hyper-dimensional mycelium that rhythmically pulses, grows, and interconnects its glowing neural networks in response to audio frequencies.

## Features
- **Organic Branching Fractal**: Smooth, SDF-based KIFS fractals that organically branch and weave like fungal threads.
- **Bioluminescent Subsurface Scattering**: Glowing tips and inner cores that mimic the translucent scattering of light through organic matter.
- **Audio-Reactive Synaptic Pulses**: Bass frequencies trigger rapid, luminous energy bursts that travel along the mycelial network.
- **Infinite Domain Spawning**: Raymarched domain repetition creates an endless, claustrophobic yet beautiful subterranean cavern filled with life.
- **Dynamic Depth of Field**: Fog and shadow calculations that give a dense, murky atmosphere to the glowing web.

## Technical Implementation
- File: public/shaders/gen-xeno-mycelial-resonance-web.wgsl
- Category: generative
- Tags: ["organic", "mycelium", "fractal", "bioluminescent", "audio-reactive", "raymarching"]
- Algorithm: Raymarching with domain repetition, smooth-min (smin) blended organic branching, and subsurface scattering approximations for glowing organic matter.

### Core Algorithm
The algorithm uses a raymarching engine with infinite domain repetition via the modulo operator. Within each repetition cell, a recursive fractal function creates branching cylindrical SDFs that are blended together using a polynomial smooth-minimum (`smin`) to ensure organic, fluid joints. Audio input (`u.config.y`) modulates the thickness of these branches and triggers traveling pulses along their length using a sine wave function based on world position and time (`u.config.x`).

### Mouse Interaction
The mouse coordinates (`u.zoom_config.y`, `u.zoom_config.z`) dynamically control the camera's rotation, allowing the user to look around the infinite web. Additionally, the proximity of the projected ray to the cursor creates a localized repelling force, gently parting the mycelial threads as if they are shying away from a light source.

### Color Mapping / Shading
Shading combines ambient occlusion with a custom subsurface scattering approximation. A dark, murky background (deep blues and purples) contrasts with the bright, glowing cyan and neon green of the mycelium. The `u.zoom_params.z` controls the hue shift of the bioluminescence, creating a living, breathing color palette.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Xeno-Mycelial Resonance-Web
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
    ripples: array<vec4<f32>, 50>
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

// PRNG and Noise
fn hash(p: vec3<f32>) -> f32 {
    let q = fract(p * 0.1031);
    return fract(q.x * q.y * q.z * (q.x + q.y + q.z));
}

// 2D Rotation Matrix
fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Smooth Minimum
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Organic Mycelial SDF
fn map(pos: vec3<f32>) -> f32 {
    var p = pos;
    // Domain repetition
    p = (fract(p / u.zoom_params.x + 0.5) - 0.5) * u.zoom_params.x;

    var d = 100.0;

    // Branching KIFS
    for (var i = 0; i < 4; i++) {
        p = abs(p) - 0.3;
        let pXY = rot2(0.5) * p.xy;
        p.x = pXY.x;
        p.y = pXY.y;
        let pYZ = rot2(1.2) * p.yz;
        p.y = pYZ.x;
        p.z = pYZ.y;

        let branch = length(p.xy) - u.zoom_params.y * (1.0 - f32(i)*0.2);
        d = smin(d, branch, 0.2);
    }

    // Audio reactive swelling
    let pulse = sin(pos.z * 5.0 - u.config.x * u.zoom_params.w) * 0.5 + 0.5;
    d -= pulse * u.config.y * 0.1;

    return d;
}

// Normal Calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(
        e.xyy * map(p + e.xyy) +
        e.yyx * map(p + e.yyx) +
        e.yxy * map(p + e.yxy) +
        e.xxx * map(p + e.xxx)
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let coords = vec2<i32>(id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(coords) - 0.5 * res) / res.y;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -3.0 + u.config.x * 0.5);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse Rotation
    let mouseX = (u.zoom_config.y - 0.5) * 6.28;
    let mouseY = (u.zoom_config.z - 0.5) * 3.14;

    let roYZ = rot2(-mouseY) * ro.yz;
    ro.y = roYZ.x;
    ro.z = roYZ.y;
    let rdYZ = rot2(-mouseY) * rd.yz;
    rd.y = rdYZ.x;
    rd.z = rdYZ.y;

    let roXZ = rot2(mouseX) * ro.xz;
    ro.x = roXZ.x;
    ro.z = roXZ.y;
    let rdXZ = rot2(mouseX) * rd.xz;
    rd.x = rdXZ.x;
    rd.z = rdXZ.y;

    // Raymarching
    var t = 0.0;
    var max_t = 20.0;
    var d = 0.0;
    for (var i = 0; i < 80; i++) {
        let p = ro + rd * t;
        d = map(p);
        if (d < 0.001 || t > max_t) { break; }
        t += d * 0.7; // step cautiously for smin
    }

    var col = vec3<f32>(0.0);

    if (t < max_t) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Base color based on hue slider
        let base_col = 0.5 + 0.5 * cos(6.28318 * (u.zoom_params.z + vec3<f32>(0.0, 0.33, 0.67)));

        // Bioluminescent Glow
        let pulse = sin(p.z * 5.0 - u.config.x * u.zoom_params.w) * 0.5 + 0.5;
        let glow = pow(pulse, 4.0) * u.config.y * 2.0;

        col = base_col * (0.2 + glow);

        // Basic lighting
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        col += diff * 0.1 * base_col;

        // Fog
        col = mix(col, vec3<f32>(0.01, 0.0, 0.02), 1.0 - exp(-0.15 * t));
    }

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
```

## Parameters (for UI sliders)

Name (default, min, max, step)
- `zoom_params.x` (Network Density): default 2.0, min 0.5, max 5.0, step 0.1
- `zoom_params.y` (Branch Thickness): default 0.15, min 0.05, max 0.5, step 0.01
- `zoom_params.z` (Bioluminescence Hue): default 0.5, min 0.0, max 1.0, step 0.01
- `zoom_params.w` (Pulse Speed): default 1.0, min 0.1, max 5.0, step 0.1

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-04-21_xeno-mycelial-resonance-web.md" "Xeno-Mycelial Resonance-Web"
Reply with only: "✅ Plan created and queued: 2026-04-21_xeno-mycelial-resonance-web.md"