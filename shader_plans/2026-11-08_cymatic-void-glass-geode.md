# New Shader Plan: Cymatic Void-Glass Geode

## Overview
A mesmerizing, infinite hollow geode formed of shimmering, iridescent "void-glass" that continuously fractures and reforms based on rhythmic cymatic frequencies. The aesthetic is simultaneously ancient geological and hyper-futuristic, contrasting absolute darkness with blinding, chromatic refractive light.

## Features
- Infinite zoom into a recursive, fractal geode structure.
- Raymarched SDFs with dynamic, frequency-based cymatic displacement.
- Iridescent, physically-based refraction (void-glass) mapping.
- Deep subsurface scattering and glowing internal energy veins.
- Gravity well distortion driven by mouse position and click state.
- Dynamic chromatic aberration that intensifies near the center of the geode.

## Technical Implementation
- File: public/shaders/gen-cymatic-void-glass-geode.wgsl
- Category: generative
- Tags: ["raymarching", "fractal", "iridescent", "cymatics", "glass"]
- Algorithm: Raymarching an Apollonian-style fractal SDF modified by multi-octave sine/cosine cymatic noise, illuminated by custom subsurface scattering and chromatic refraction logic.

### Core Algorithm
Raymarching loop stepping through an SDF built from an inverted sphere (the hollow cavity) and folded space (using `abs(p)` and rotational folds). The surface of the SDF is displaced by a time-varying cymatic function: `sin(length(p) * frequency - u.config.x) * cos(atan2(p.y, p.x) * angular_frequency)`. This creates standing wave patterns. The fractal structure uses Apollonian gasket folding techniques to create infinite detail.

### Mouse Interaction
The mouse acts as a localized gravity well. When `u.zoom_config.w > 0.5` (pressed), it pulls the ray direction and locally warps the SDF domain towards `u.zoom_config.yz`, creating a vortex effect. The distortion formula is `p += normalize(mouse_pos - p) * gravity_strength / (length(mouse_pos - p) + 0.1)`.

### Color Mapping / Shading
Shading involves calculating the normal of the SDF and simulating refraction by bending the view ray. The "void-glass" effect uses an environment map lookup (procedurally generated based on direction) combined with a Fresnel term. Iridescence is applied by modulating the reflection color based on the dot product of the normal and view vector, mapped through a palette function. Internal glowing veins are added based on the orbit trap (distance to origin during fractal folding).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Cymatic Void-Glass Geode
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
  config: vec4<f32>,              // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,         // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,         // .xyzw = user params p1..p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

// ----------------------------------------------------------------

const MAX_STEPS = 100;
const SURF_DIST = 0.001;
const MAX_DIST = 10.0;

// Palette function for iridescence
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// 2D Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// SDF with Apollonian fractal and Cymatic displacement
fn map(p: vec3<f32>) -> vec2<f32> { // returns vec2(distance, orbit_trap)
    var q = p;
    let time = u.config.x * u.zoom_params.x; // Speed param

    // Mouse gravity well distortion
    let mouse_uv = u.zoom_config.yz * 2.0 - 1.0;
    let mouse_pos = vec3<f32>(mouse_uv.x, -mouse_uv.y, 0.0);
    if (u.zoom_config.w > 0.5) {
        let dir = mouse_pos - q;
        let dist = length(dir);
        q += normalize(dir) * (0.5 * u.zoom_params.w) / (dist + 0.1); // Gravity param
    }

    var scale = 1.0;
    var orb = 1000.0;

    // Apollonian folding
    for (var i = 0; i < 4; i++) {
        q = -1.0 + 2.0 * fract(0.5 * q + 0.5);
        let r2 = dot(q, q);
        orb = min(orb, r2);
        let k = 1.2 / r2;
        q *= k;
        scale *= k;

        let a = float(i) * 0.5 + time * 0.1;
        q.x = q.x * cos(a) - q.y * sin(a); // manual rot for x/y
        q.y = q.y * cos(a) + q.x * sin(a);
    }

    let base_sdf = (length(q) - 0.25) / scale;

    // Cymatic displacement
    let freq = u.zoom_params.y * 10.0; // Frequency param
    let amp = u.zoom_params.z * 0.1;   // Amplitude param
    let disp = sin(length(p) * freq - time) * cos(atan2(p.y, p.x) * 4.0) * amp;

    return vec2<f32>(base_sdf + disp, orb);
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> { // returns vec3(distance, steps, orbit_trap)
    var dO = 0.0;
    var min_orb = 1000.0;
    var i = 0;
    for (; i < MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let res = map(p);
        let dS = res.x;
        min_orb = min(min_orb, res.y);
        dO += dS;
        if (dO > MAX_DIST || abs(dS) < SURF_DIST) { break; }
    }
    return vec3<f32>(dO, float(i), min_orb);
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.zw);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    var uv = (fragCoord - 0.5 * res) / res.y;
    let time = u.config.x;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -2.0 + sin(time*0.2)*0.5); // Slight dolly
    let lookat = vec3<f32>(0.0, 0.0, 0.0);
    let zoom = 1.0;

    let f = normalize(lookat - ro);
    let r = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), f));
    let u_cam = cross(f, r);
    var rd = normalize(uv.x * r + uv.y * u_cam + f * zoom);

    // Raymarch
    let rm = raymarch(ro, rd);
    let d = rm.x;
    let steps = rm.y;
    let orb = rm.z;

    var col = vec3<f32>(0.0);

    if (d < MAX_DIST) {
        let p = ro + rd * d;
        let n = calcNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let viewDir = normalize(ro - p);

        // Iridescence (Void-Glass effect)
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 5.0);
        let iri_color = palette(fresnel + orb * 0.1,
                                vec3(0.5, 0.5, 0.5),
                                vec3(0.5, 0.5, 0.5),
                                vec3(1.0, 1.0, 1.0),
                                vec3(0.0, 0.33, 0.67));

        // Inner Glow (Veins)
        let glow = exp(-orb * 5.0) * vec3<f32>(0.2, 0.8, 1.0);

        col = (diff * 0.2 + iri_color * 0.8) * (1.0 - fresnel * 0.5) + glow;

        // Subsurface scattering approximation based on step count
        col += vec3<f32>(0.1, 0.05, 0.2) * (steps / float(MAX_STEPS));
    } else {
        // Deep space background
        col = vec3<f32>(0.0, 0.0, 0.02) * (1.0 - length(uv));
    }

    // Gamma correction
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
```

## Parameters (for UI sliders)

- `speed` (1.0, 0.1, 5.0, 0.1) - Controls the animation speed of the fractal and cymatics (mapped to `u.zoom_params.x`)
- `cymatic_freq` (1.0, 0.1, 5.0, 0.1) - Frequency of the cymatic standing waves (mapped to `u.zoom_params.y`)
- `cymatic_amp` (1.0, 0.0, 5.0, 0.1) - Amplitude of the cymatic displacement (mapped to `u.zoom_params.z`)
- `gravity_strength` (1.0, 0.0, 5.0, 0.1) - Strength of the mouse gravity well effect (mapped to `u.zoom_params.w`)

## Integration Steps

1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
