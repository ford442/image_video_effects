# New Shader Plan: Ethereal Chrono-Flora Loom

## Overview
A mesmerizing, luminescent botanical matrix that weaves organic fractal geometry with time-dilating quantum energy threads, invoking the feeling of an alien greenhouse frozen in a dimension of light.

## Features
- **Bioluminescent Strands:** Generative, glowing energy fibers that grow and weave through space.
- **Time-Dilating Pulsations:** Central blooms that warp the surrounding light and time-field, pulsing rhythmically.
- **Fractal Botanical Forms:** Non-Euclidean petal and leaf structures defined by recursive SDFs.
- **Quantum Spores:** Floating particles of light that orbit the central structure and react to the gravitational field.
- **Holographic Chromatic Aberration:** Edge-lit dispersion effects that split light into spectrums at grazing angles.
- **Fluid Ambient Caustics:** A backdrop of shifting, watery light rays that illuminate the flora.
- **Interactive Gravitational Disturbance:** Mouse interaction bends the stems and disturbs the spore orbits.

## Technical Implementation
- File: public/shaders/gen-ethereal-chrono-flora-loom.wgsl
- Category: generative
- Tags: ["organic", "botanical", "quantum", "fractal", "luminescent"]
- Algorithm: Raymarching through a domain-warped fractal SDF with layered noise for fluid motion and glowing volumetric light accumulation.

### Core Algorithm
The core is a raymarching loop evaluating a complex SDF. The main structure uses a domain-folded cylindrical coordinate system (polar repetition) to create petal-like arrangements. We use smooth minimums (`smin`) to blend a central pulsing orb with sweeping, twisted helix strands. The space itself is deformed using 3D Simplex noise to give an organic, underwater-like flowing movement over time. Volumetric glow is accumulated during the raymarch step based on proximity to the glowing strands.

### Mouse Interaction
When `u.zoom_config.w > 0.0`, the mouse acts as a localized gravity well. The ray origin and direction are slightly bent towards the mouse position, and the SDF field applies a localized spatial twist, mimicking physical interaction with the ethereal flora. The intensity of the twist is inversely proportional to the distance from the mouse pointer.

### Color Mapping / Shading
Shading relies heavily on an emissive glowing palette. The base material of the flora has a nacreous, iridescent subsurface scattering effect using a dot product of the normal and the view direction. Glowing strands accumulate pure emissive color (cyan, magenta, and gold) using a branchless cosine palette. Bloom is simulated by accumulating distance thresholds during raymarching.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Ethereal Chrono-Flora Loom
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Density, .y = Flow Speed, .z = Glow Intensity, .w = Color Shift
  ripples: array<vec4<f32>, 50>,
};

// --- CONSTANTS ---
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 50.0;
const SURF_DIST: f32 = 0.001;

// --- UTILS ---
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(6.28318 * (c * t + d));
}

// --- SDF ---
fn map(p: vec3<f32>) -> vec2<f32> {
    var p_mod = p;
    let t = u.config.x * u.zoom_params.y;

    // Twist based on height and time
    let pxy = p_mod.xy * rot2D(p_mod.z * 0.2 + t * 0.5);
    p_mod = vec3<f32>(pxy, p_mod.z);

    // Domain repetition for flora petals
    let angle = atan2(p_mod.y, p_mod.x);
    let radius = length(p_mod.xy);
    let petals = 6.0;
    let sector = 6.28318 / petals;
    let id = floor(angle / sector);
    let local_angle = (fract(angle / sector) - 0.5) * sector;

    let p_folded = vec3<f32>(cos(local_angle)*radius, sin(local_angle)*radius, p_mod.z);

    // Flora structure (capsule/cylinder)
    let d_stem = length(p_folded.xy - vec2<f32>(0.5, 0.0)) - 0.1 * u.zoom_params.x;

    // Central glowing orb
    let d_orb = length(p) - 1.0;

    let d = smin(d_stem, d_orb, 0.5);

    return vec2<f32>(d, 1.0);
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p).x;
    let n = vec3<f32>(
        d - map(p - e.xyy).x,
        d - map(p - e.yxy).x,
        d - map(p - e.yyx).x
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;

    var ro = vec3<f32>(0.0, 0.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse Interaction
    if (u.zoom_config.w > 0.0) {
        let mouse_uv = (u.zoom_config.yz - 0.5 * res) / res.y;
        let pxy = ro.xy * rot2D(mouse_uv.x * 3.14);
        ro = vec3<f32>(pxy, ro.z);
    }

    var t = 0.0;
    var glow = 0.0;
    var hit = false;

    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * t;
        let d = map(p);

        glow += 0.01 / (0.01 + abs(d.x)) * u.zoom_params.z;

        if (abs(d.x) < SURF_DIST) {
            hit = true;
            break;
        }
        if (t > MAX_DIST) {
            break;
        }
        t += d.x * 0.8;
    }

    var col = vec3<f32>(0.0);

    if (hit) {
        let p = ro + rd * t;
        let n = getNormal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));

        let dif = clamp(dot(n, l), 0.0, 1.0);
        let amb = 0.1 + 0.9 * clamp(0.5 + 0.5 * n.y, 0.0, 1.0);

        let baseCol = palette(length(p) * 0.1 + u.zoom_params.w);
        col = baseCol * dif * amb;
    }

    // Add glow
    col += palette(u.config.x * 0.1) * glow * 0.05;

    // Output
    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(t / MAX_DIST));
    textureStore(dataTextureA, id.xy, vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Density (1.0, 0.1, 5.0, 0.1) -> Maps to `zoom_params.x`
- Flow Speed (1.0, 0.0, 5.0, 0.1) -> Maps to `zoom_params.y`
- Glow Intensity (1.0, 0.0, 5.0, 0.1) -> Maps to `zoom_params.z`
- Color Shift (0.0, 0.0, 1.0, 0.01) -> Maps to `zoom_params.w`

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
