# New Shader Plan: Celestial Aether-Seraphim Wings

## Overview
A majestic, hyper-dimensional array of ethereal, fractal wings woven from liquid plasma and quantum light that endlessly fold, beat, and shatter into geometric feathers in response to cosmic audio resonance.

## Features
- **Fractal Wing-Geometry**: Recursive KIFS-based (Kaleidoscopic Iterated Function Systems) geometry forming impossibly intricate, layered wing structures.
- **Volumetric Plasma Plumes**: Ethereal, glowing plasma that flows over the geometric wing edges, imitating the soft scattering of cosmic feathers.
- **Audio-Reactive Beating & Shattering**: Bass impacts violently fracture the wings into sharp, glowing polygons that smoothly reassemble over time, while the entire structure beats to the global tempo.
- **Iridescent Quantum Shading**: A continuously shifting chromatic aberration and thin-film interference lighting model that gives the wings an otherworldly, pearlescent glow.
- **Infinite Ascent**: The camera dynamically moves upwards through an endless corridor of falling, glowing wing-fragments and glowing plasma ribbons.

## Technical Implementation
- File: public/shaders/gen-celestial-aether-seraphim-wings.wgsl
- Category: generative
- Tags: ["wings", "angelic", "plasma", "fractal", "audio-reactive", "raymarching"]
- Algorithm: Advanced raymarching with specialized KIFS fractals for wing-like folding, smooth-min for plasma blending, and dynamic domain distortion.

### Core Algorithm
The algorithm uses a volumetric raymarching engine. The primary SDF is a KIFS fractal that folds space multiple times along the X and Y axes, scaled and rotated over iterations to form the distinct layered shape of a wing. A secondary SDF, using a smooth-minimum (`smin`), blends soft cylindrical shapes representing glowing plasma veins running through the wings. Audio input (`u.config.y`) modulates the fold angles and distance thresholds, creating the effect of beating wings and fracturing feathers.

### Mouse Interaction
The mouse coordinates (`u.zoom_config.y`, `u.zoom_config.z`) act as an interactive gravity well and light source. Moving the mouse dynamically shifts the angle of incidence for the iridescent shading and repels the falling fractal feathers, creating a wake of chaotic turbulence through the infinite ascent.

### Color Mapping / Shading
The shading relies on a bespoke thin-film interference function combined with standard ambient occlusion. The surface color transitions between deep celestial blues, vibrant magenta, and searing gold based on the normal vector's angle to the view direction and the `u.zoom_params.z` parameter. Glowing elements are accumulated during the raymarching loop, blooming intensely where the plasma veins intersect the fractal geometry.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Celestial Aether-Seraphim Wings
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

// --- SHADER LOGIC ---

// 2D Rotation
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Smooth Min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Wing SDF (KIFS Fractal)
fn map(pos: vec3<f32>) -> f32 {
    var p = pos;
    // Ascent over time
    p.y += u.config.x * 2.0 * u.zoom_params.w;

    // Domain Repetition
    p.y = (fract(p.y / 8.0 + 0.5) - 0.5) * 8.0;

    var d = 1000.0;

    // Base fold
    p.x = abs(p.x);

    let time = u.config.x * 0.5;
    let beat = sin(time * 3.14 + u.config.y * 2.0) * 0.2;

    for (var i = 0; i < 5; i++) {
        p.x = abs(p.x) - u.zoom_params.x * 1.5;
        p.y = abs(p.y) - 0.5;
        p.z = abs(p.z) - 0.2;

        let pXY = rot(0.4 + beat) * p.xy;
        p.x = pXY.x;
        p.y = pXY.y;

        let pYZ = rot(0.2 - beat*0.5) * p.yz;
        p.y = pYZ.x;
        p.z = pYZ.y;

        // Wing feather structures
        let feather = length(p.xz) - u.zoom_params.y * (1.0 - f32(i) * 0.15);
        d = smin(d, feather, 0.3);
    }

    // Audio reactive fracturing
    let fracture = sin(pos.x * 10.0) * cos(pos.y * 10.0) * sin(pos.z * 10.0);
    d += fracture * u.config.y * 0.1;

    return d;
}

// Normal Calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.001;
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

    var ro = vec3<f32>(0.0, -2.0, -5.0 + u.config.x * 0.2);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse Interaction
    let mouseX = (u.zoom_config.y - 0.5) * 6.28;
    let mouseY = (u.zoom_config.z - 0.5) * 3.14;

    let roYZ = rot(-mouseY) * ro.yz;
    ro.y = roYZ.x;
    ro.z = roYZ.y;
    let rdYZ = rot(-mouseY) * rd.yz;
    rd.y = rdYZ.x;
    rd.z = rdYZ.y;

    let roXZ = rot(mouseX) * ro.xz;
    ro.x = roXZ.x;
    ro.z = roXZ.y;
    let rdXZ = rot(mouseX) * rd.xz;
    rd.x = rdXZ.x;
    rd.z = rdXZ.y;

    var t = 0.0;
    var max_t = 30.0;
    var d = 0.0;
    var glow = 0.0;

    for (var i = 0; i < 90; i++) {
        let p = ro + rd * t;
        d = map(p);

        // Accumulate glow near surfaces
        glow += 0.01 / (0.01 + abs(d));

        if (d < 0.001 || t > max_t) { break; }
        t += d * 0.6; // Smaller step size for safety with smin and domain mod
    }

    var col = vec3<f32>(0.0);

    if (t < max_t) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        let viewDir = normalize(ro - p);
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);

        // Thin-film interference iridescence
        let hue = fract(u.zoom_params.z + t * 0.1 + fresnel * 0.5);
        let base_col = 0.5 + 0.5 * cos(6.28318 * (vec3<f32>(hue) + vec3<f32>(0.0, 0.33, 0.67)));

        col = base_col * (0.2 + fresnel * 0.8);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        col += diff * 0.3 * base_col;

        // Audio reactive brightness
        col += vec3<f32>(u.config.y * 1.5) * fresnel * base_col;
    }

    // Add volumetric glow
    let glowCol = 0.5 + 0.5 * cos(6.28318 * (u.zoom_params.z + vec3<f32>(0.5, 0.0, 0.2)));
    col += glow * 0.015 * glowCol;

    // Atmospheric Fog
    col = mix(col, vec3<f32>(0.01, 0.02, 0.05), 1.0 - exp(-0.05 * t));

    // Gamma correction
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
```

## Parameters (for UI sliders)

Name (default, min, max, step)
- `zoom_params.x` (Fractal Spread): default 1.0, min 0.1, max 3.0, step 0.1
- `zoom_params.y` (Feather Thickness): default 0.2, min 0.05, max 1.0, step 0.01
- `zoom_params.z` (Iridescence Hue): default 0.2, min 0.0, max 1.0, step 0.01
- `zoom_params.w` (Ascent Speed): default 1.0, min 0.0, max 5.0, step 0.1

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-05-30_celestial-aether-seraphim-wings.md" "Celestial Aether-Seraphim Wings"
Reply with only: "✅ Plan created and queued: 2026-05-30_celestial-aether-seraphim-wings.md"
