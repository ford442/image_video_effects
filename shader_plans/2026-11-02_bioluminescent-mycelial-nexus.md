# New Shader Plan: Bioluminescent Mycelial Nexus

## Overview
A hyper-organic, pulsing network of luminous fungal threads that weave and branch through a dense, volumetric void, reacting dynamically to bass and treble frequencies.

## Features
- Infinite, branching mycelial tendrils using a domain-warped 3D SDF.
- Deep subsurface scattering and bioluminescent glowing tips.
- Audio-reactive pulsing along the threads (bass drives thickness, treble drives glow intensity).
- Volumetric fog and ambient spore particles floating through the network.
- Mouse interaction acts as a gravity well, pulling tendrils and spores towards the cursor.

## Technical Implementation
- File: public/shaders/gen-bioluminescent-mycelial-nexus.wgsl
- Category: generative
- Tags: ["organic", "bioluminescent", "audio-reactive", "network", "sdf"]
- Algorithm: Raymarching a domain-repetition SDF of branching cylinders, layered with 3D noise for organic displacement and audio-reactive emissive shading.

### Core Algorithm
Raymarching scene where the base geometry consists of repeating smooth-blended cylinders (`smin`). The space is warped using 3D fractional Brownian motion (fBM) to give the threads a gnarly, organic appearance. Spores are rendered as scattered points in the domain.

### Mouse Interaction
The `u.zoom_config` vector (when `w > 0.5`) creates a spherical distortion field. The distance from the ray position to the mouse world-position is calculated, applying an inverse-square attraction force that bends the space (and thus the tendrils) towards the cursor.

### Color Mapping / Shading
Deep purples and indigos for the void/background. The tendrils have a base translucent white/blue, transitioning into bright cyan and neon green at their tips. Shading incorporates pseudo-subsurface scattering (evaluating lighting slightly inside the surface) and a heavy emissive term driven by `plasmaBuffer[0]` (bass/mids/treble).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Bioluminescent Mycelial Nexus
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

// --- IMPLEMENTATION SKELETON ---

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    let n = i.x + i.y * 157.0 + 113.0 * i.z;
    return fract(sin(n) * 43758.5453123);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var pp = p;
    for(var i=0; i<4; i++) {
        f += w * noise3D(pp);
        w *= 0.5;
        pp *= 2.0;
    }
    return f;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(p: vec3<f32>) -> f32 {
    var pos = p;

    if (u.zoom_config.w > 0.5) {
        let mouseWorld = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (u.zoom_config.z - 0.5) * -5.0, 0.0);
        let dist = length(pos - mouseWorld);
        let pull = 1.0 / (1.0 + dist * dist);
        pos = mix(pos, mouseWorld, pull * 0.2);
    }

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let thickness = 0.05 + bass * 0.05;

    pos += fbm(pos * 2.0 + u.config.x * 0.5) * 0.5;
    let cell = fract(pos) - 0.5;

    let d1 = length(cell.xy) - thickness;
    let d2 = length(cell.yz) - thickness;
    let d3 = length(cell.xz) - thickness;

    let d = smin(smin(d1, d2, 0.1), d3, 0.1);
    return d;
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }
    let uv = (vec2<f32>(id.xy) - 0.5 * resolution) / resolution.y;

    let time = u.config.x * 0.5;
    let ro = vec3<f32>(sin(time) * 2.0, cos(time*0.5) * 2.0, time * 2.0);
    let ta = ro + vec3<f32>(sin(time*0.7), cos(time*0.3), 1.0);
    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));
    let rd = normalize(uv.x * cu + uv.y * cv + 1.0 * cw);

    var t = 0.0;
    var d = 0.0;
    var p = ro;
    for(var i=0; i<80; i++) {
        p = ro + rd * t;
        d = map(p);
        if (d < 0.001 || t > 20.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.02, 0.01, 0.05);

    if (d < 0.001) {
        let n = getNormal(p);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);

        let sss = smoothstep(0.0, 0.5, map(p + lightDir * 0.1)) * 0.5;

        let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
        let emit = pow(max(0.0, sin(p.z * 10.0 - u.config.x * 5.0)), 4.0) * treble;

        let baseCol = mix(vec3<f32>(0.1, 0.4, 0.8), vec3<f32>(0.1, 0.8, 0.4), fract(p.z * 0.2));
        col = baseCol * (diff + sss * 0.5) + emit * vec3<f32>(0.2, 1.0, 0.8) * 2.0;
    }

    col = mix(col, vec3<f32>(0.02, 0.01, 0.05), 1.0 - exp(-0.05 * t));
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)

Branching Density (2.0, 0.1, 5.0, 0.1)
Glow Intensity (1.0, 0.0, 3.0, 0.1)
Network Mutation Speed (1.0, 0.0, 3.0, 0.1)
Subsurface Scattering (0.5, 0.0, 1.0, 0.05)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
