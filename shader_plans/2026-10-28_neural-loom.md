# New Shader Plan: Neural Loom

## Overview
A biomechanical network of pulsating synapses that weaves intricate web structures over time.

## Features
- Dynamic recursive web structures based on audio reactivity
- Procedural generation of organic synapse connections
- Color mapped to frequency bands (bass/mids/treble) using plasmaBuffer[0]
- Mouse interaction warps the spatial grid when actively clicked
- Subsurface scattering effect on thicker web structures

## Technical Implementation
- File: public/shaders/gen-neural-loom.wgsl
- Category: generative
- Tags: ["organic", "audio-reactive", "network", "SDF"]
- Algorithm: Raymarching against a complex domain-repeated and recursively folded SDF

### Core Algorithm
Using a recursive fold algorithm (e.g., KIFS or spherical folding), we define a space that produces web-like filaments. These filaments are then domain repeated to form a network. The widths of the filaments oscillate based on audio frequencies.

### Mouse Interaction
When `u.zoom_config.w > 0.5` (mouse is pressed), apply a vortex distortion to the ray origin or SDF domain around the mouse coordinates (`u.zoom_config.yz`).

### Color Mapping / Shading
Base colors are mapped to frequency (bass = red, mids = green, treble = blue). Shading uses a fake subsurface scattering model by accumulating density along the ray edge, giving the webs a translucent, organic appearance.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Neural Loom
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

// ============================================================================
// Shader Implementation
// ============================================================================

// Helper functions for math and noise
fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D rotation matrix
fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}
fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}
fn rotZ(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

// Simple fractal noise / FBM
fn hash(p: vec3<f32>) -> f32 {
    let q = fract(p * vec3<f32>(17.1, 31.7, 47.9));
    return fract(sin(dot(q, vec3<f32>(12.9898, 78.233, 54.53))) * 43758.5453);
}

fn noise(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f = f * f * (3.0 - 2.0 * f);

    let n = p.x + p.y * 157.0 + 113.0 * p.z;
    return mix(
        mix(mix(hash(p + vec3<f32>(0.0, 0.0, 0.0)), hash(p + vec3<f32>(1.0, 0.0, 0.0)), f.x),
            mix(hash(p + vec3<f32>(0.0, 1.0, 0.0)), hash(p + vec3<f32>(1.0, 1.0, 0.0)), f.x), f.y),
        mix(mix(hash(p + vec3<f32>(0.0, 0.0, 1.0)), hash(p + vec3<f32>(1.0, 0.0, 1.0)), f.x),
            mix(hash(p + vec3<f32>(0.0, 1.0, 1.0)), hash(p + vec3<f32>(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

// Distance to a line segment
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// Map function (SDF)
fn map(pos: vec3<f32>, bass: f32, mids: f32, treble: f32) -> f32 {
    var p = pos;
    let t = u.config.x;

    // Global distortion from noise
    p += noise(p * 2.0 + t * 0.5) * 0.2;

    // Domain repetition
    let spacing = 4.0;
    p = (fract((p + spacing/2.0) / spacing) - 0.5) * spacing;

    // Rotation based on time and audio
    p = p * rotY(t * 0.2 + bass * 0.5) * rotX(t * 0.15 + mids * 0.3);

    // Recursive folding (KIFS-like) to create network structure
    var d = 100.0;
    let iterations = 4;
    var scale = 1.0;

    // Base node position
    let center = vec3<f32>(0.0);

    // Dynamic radius influenced by audio and UI parameters
    // u.zoom_params.x = Web Density
    // u.zoom_params.w = Audio Reactivity
    let baseRadius = 0.05 * u.zoom_params.x;
    let audioRadius = (bass * 0.1 + mids * 0.05 + treble * 0.02) * u.zoom_params.w;
    let r = baseRadius + audioRadius;

    // Center node
    d = min(d, length(p) - r * 2.0);

    for (var i = 0; i < iterations; i++) {
        p = abs(p) - vec3<f32>(0.5, 0.4, 0.6) * scale;
        p = p * rotZ(0.2) * rotY(0.3);

        // Connect nodes
        d = min(d, sdCapsule(p, vec3<f32>(0.0), vec3<f32>(0.5, 0.4, 0.6) * scale, r * (1.0 - f32(i)/f32(iterations))));

        scale *= 0.7;
    }

    return d;
}

// Normal calculation
fn calcNormal(p: vec3<f32>, bass: f32, mids: f32, treble: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, bass, mids, treble) - map(p - e.xyy, bass, mids, treble),
        map(p + e.yxy, bass, mids, treble) - map(p - e.yxy, bass, mids, treble),
        map(p + e.yyx, bass, mids, treble) - map(p - e.yyx, bass, mids, treble)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) {
        return;
    }

    // Audio data from plasmaBuffer
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    // Normalize UVs (-1 to 1)
    var uv = (vec2<f32>(global_id.xy) - 0.5 * res) / min(res.x, res.y);
    // Flip Y for standard screen coordinates
    uv.y = -uv.y;

    let t = u.config.x;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, 3.0 - t * 1.5);
    let target = ro + vec3<f32>(0.0, 0.0, -1.0);
    let up = vec3<f32>(0.0, 1.0, 0.0);

    let ww = normalize(target - ro);
    let uu = normalize(cross(ww, up));
    let vv = normalize(cross(uu, ww));
    var rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    // Mouse Interaction: Vortex / Gravity Well
    // u.zoom_params.z = Vortex Strength
    if (u.zoom_config.w > 0.5) {
        let mouse_uv = u.zoom_config.yz * vec2<f32>(1.0, -1.0) + vec2<f32>(0.0, 1.0);
        let screen_mouse = (mouse_uv * res - 0.5 * res) / min(res.x, res.y);

        let mouse_dir = normalize(screen_mouse.x * uu + screen_mouse.y * vv + 1.5 * ww);

        // Bend ray direction towards mouse
        let pull = max(0.0, 1.0 - length(uv - screen_mouse));
        rd = normalize(mix(rd, mouse_dir, pull * u.zoom_params.z));
    }

    // Raymarching
    var dO = 0.0;
    var p = ro;
    var hit = false;
    let maxSteps = 100;
    let maxDist = 20.0;
    let surfDist = 0.001;

    for (var i = 0; i < maxSteps; i++) {
        p = ro + rd * dO;
        let dS = map(p, bass, mids, treble);
        dO += dS;

        if (dS < surfDist) {
            hit = true;
            break;
        }
        if (dO > maxDist) {
            break;
        }
    }

    // Shading
    var col = vec3<f32>(0.0);

    // Background color (dark abyss)
    let bgCol = vec3<f32>(0.02, 0.03, 0.05);

    if (hit) {
        let n = calcNormal(p, bass, mids, treble);

        // Basic lighting
        let lightPos = ro + vec3<f32>(2.0, 2.0, 0.0);
        let l = normalize(lightPos - p);
        let dif = max(dot(n, l), 0.0);

        // Base color mapping based on audio and position
        let nodeDist = length(fract((p + 2.0)/4.0) - 0.5); // approximate distance to node centers
        let colorMix = vec3<f32>(
            bass * 1.5 * (1.0 - nodeDist),
            mids * 1.2,
            treble * 2.0 * nodeDist
        );
        let baseCol = vec3<f32>(0.2, 0.5, 0.8) + colorMix * 0.5;

        // Subsurface scattering approximation (glow)
        // Accumulate inverse distances
        var sss = 0.0;
        let sssSteps = 5;
        let sssStepSize = 0.1;
        for(var j=1; j<=sssSteps; j++) {
            let sssDist = f32(j) * sssStepSize;
            let sssP = p + n * sssDist;
            let sssD = map(sssP, bass, mids, treble);
            sss += max(0.0, sssDist - sssD) * 0.5;
        }

        // u.zoom_params.y = Glow Intensity
        let glow = sss * u.zoom_params.y;

        // Fresnel
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        col = baseCol * dif;
        col += baseCol * glow;
        col += vec3<f32>(1.0) * fresnel * 0.5; // Edge rim light

        // Distance fog
        col = mix(col, bgCol, smoothstep(5.0, maxDist, dO));
    } else {
        col = bgCol;
    }

    // Output
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)
Web Density (5.0, 1.0, 10.0, 0.1)
Glow Intensity (1.0, 0.0, 2.0, 0.05)
Vortex Strength (0.5, 0.0, 1.0, 0.01)
Audio Reactivity (1.0, 0.0, 2.0, 0.1)

Integration Steps
Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-10-28_neural-loom.md" "Neural Loom"
