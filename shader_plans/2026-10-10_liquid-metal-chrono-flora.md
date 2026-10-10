# New Shader Plan: Liquid-Metal Chrono-Flora

## Overview
A hyper-fluid, metallic botanical structure that continuously blossoms and folds in upon itself, seemingly driven by temporal anomalies and magnetic forces.

## Features
- Dynamic recursive SDF-based folding flowers
- Liquid mercury/chrome material shading with intense specular highlights
- Temporal distortion waves causing time-reversed ripples in the geometry
- Mouse-interactive gravity wells pulling the metallic tendrils
- Audio-reactive blooming mapped to the bass and treble frequencies
- Subsurface pseudo-refraction for internal glow effects
- Smooth blending using polynomial min/max for organic connectivity

## Technical Implementation
- File: public/shaders/gen-liquid-metal-chrono-flora.wgsl
- Category: generative
- Tags: ["organic", "metal", "time", "fluid", "sdf"]
- Algorithm: Raymarching with recursive domain distortion and temporal phase shifting.

### Core Algorithm
The base geometry is a layered SDF combining distorted tori and spheres to form petals. The space is twisted radially (`atan2` + polar coordinates) and repeated with smooth minimum functions (`smin`). A global temporal parameter (`u.config.x`) modulates the scale and twist frequency, creating the "chrono" effect where the blooming appears to breathe or reverse locally.

### Mouse Interaction
The mouse coordinates (`u.zoom_config.yz`) map to a 3D gravity well in the scene. When pressed (`u.zoom_config.w > 0.0`), the metallic flora tendrils are pulled toward the pointer using an exponential falloff distortion vector, causing the liquid metal to stretch elastically.

### Color Mapping / Shading
Uses a highly reflective physical-based shading model. The normal vectors drive a fake environment map lookup for chrome reflections. Dark recesses get a deep, ambient purple/magenta hue representing the "chrono energy," while the tips are bright silver/gold.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Liquid-Metal Chrono-Flora
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

// Utility Functions
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn rot2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// Map function
fn map(p: vec3<f32>) -> f32 {
    var pos = p;

    // Mouse distortion
    if (u.zoom_config.w > 0.0) {
        // Implement mouse gravity well
        let m = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
        let dist = length(pos.xy - m);
        let pull = exp(-dist * 2.0) * 0.5;
        pos -= vec3<f32>(m * pull, 0.0);
    }

    // Audio reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);

    // Core geometry
    let time = u.config.x * 0.5;

    // Domain distortion and SDF combination logic goes here

    return length(pos) - 1.0 - bass * 0.2; // Placeholder sphere
}

// Compute Normal
fn get_normal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.zw);
    let coords = vec2<f32>(id.xy);
    if (coords.x >= dims.x || coords.y >= dims.y) { return; }

    let uv = (coords - 0.5 * dims) / min(dims.x, dims.y);

    var ro = vec3<f32>(0.0, 0.0, -3.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if (d < 0.001 || t > 10.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    var out_depth = 1.0;

    if (t < 10.0) {
        let p = ro + rd * t;
        let n = get_normal(p);

        // Liquid metal shading
        let viewDir = normalize(ro - p);
        let refl = reflect(-viewDir, n);

        // Base chrome reflection
        let envCol = vec3<f32>(0.8, 0.9, 1.0) * max(0.0, refl.y * 0.5 + 0.5);

        // Chrono energy in crevices
        let ao = clamp(map(p + n * 0.1) * 10.0, 0.0, 1.0);
        let energyCol = vec3<f32>(0.8, 0.1, 0.9) * (1.0 - ao);

        col = envCol + energyCol;

        // Specular
        let spec = pow(max(dot(refl, normalize(vec3<f32>(1.0, 1.0, -1.0))), 0.0), 32.0);
        col += vec3<f32>(1.0) * spec;

        out_depth = t / 10.0;
    }

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(out_depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(0.0));
}
```

Parameters (for UI sliders)
- Metallic Shine (default 0.8, min 0.0, max 1.0, step 0.01)
- Bloom Speed (default 1.0, min 0.1, max 5.0, step 0.1)
- Temporal Distortion (default 0.5, min 0.0, max 1.0, step 0.01)
- Chrono Color Intensity (default 0.7, min 0.0, max 1.0, step 0.01)

Integration Steps
1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
