# New Shader Plan: Prismatic Bismuth Labyrinth

## Overview
A slowly evolving, raymarched cubic labyrinth that fractures and recrystallizes, evoking the vibrant, geometric, and iridescent formations of bismuth crystals. The vibe is a synthetic yet organic fusion of sharp architecture and fluid color gradients.

## Features
- Generates a continuous, pseudo-infinite labyrinth of interconnected cubic blocks.
- Employs domain repetition with varied block scales to break monotony.
- Surfaces feature iridescent color mapping based on surface normals and view angle.
- Uses noise to simulate stepped, hopper-like crystal growth patterns on the blocks.
- Mouse interaction warps the spatial grid, creating localized gravity wells or black hole-like distortions.
- Soft shadows and ambient occlusion enhance depth and structural clarity.
- Subtle bloom simulates the intense specular highlights of metallic bismuth.

## Technical Implementation
- File: public/shaders/gen-prismatic-bismuth-labyrinth.wgsl
- Category: generative
- Tags: ["bismuth", "fractal", "raymarching", "iridescent", "geometry", "organic"]
- Algorithm: Raymarching an SDF of repeated, modified cubes with space folding.

### Core Algorithm
The base geometry is a box SDF repeated infinitely using `fract()` or a specialized `opRep` function. To create the stepped, hopper-crystal look of bismuth, the SDF incorporates a quantized or stepped coordinate modification based on distance from the cell center, offset by fractional Brownian motion (fBm) noise.

### Mouse Interaction
The mouse acts as a localized spatial distortion field. When active (`u.zoom_config.w > 0.5`), the ray's origin and direction are slightly bent toward or away from the mouse's mapped 3D position in the scene. The distortion is a Gaussian function of distance: `distortion = strength * exp(-dist * dist / radius)`.

### Color Mapping / Shading
Colors are driven by a palette function commonly used for iridescence (e.g., cosine-based palettes like `a + b*cos(2.0*PI*(c*t+d))`). The input `t` to this palette is a combination of the surface normal, the view direction (Fresnel effect), and the block's unique ID from the domain repetition, resulting in shimmering, multi-colored metallic facets.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Prismatic Bismuth Labyrinth
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

const MAX_STEPS = 100;
const SURF_DIST = 0.001;
const MAX_DIST = 100.0;
const PI = 3.14159265359;

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Cosine based palette for iridescence
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(6.28318 * (c * t + d));
}

// 3D Noise for step variation
fn hash31(p: vec3<f32>) -> f32 {
    let p1 = fract(p * 0.1031);
    let p2 = p1 + dot(p1, p1.zyx + 31.32);
    return fract((p2.x + p2.y) * p2.z);
}

// Box SDF
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}

// Map function for the scene
fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;

    // Mouse distortion
    if (u.zoom_config.w > 0.5) {
        let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 10.0, (u.zoom_config.z - 0.5) * 10.0, 0.0);
        let dist = length(p.xy - mouse_pos.xy);
        let warp = exp(-dist * dist * u.zoom_params.x) * u.zoom_params.y;
        p.x -= warp * (p.x - mouse_pos.x);
        p.y -= warp * (p.y - mouse_pos.y);
    }

    // Domain repetition
    let c = 2.0;
    let id = floor((p + c * 0.5) / c);
    p = (p + c * 0.5) - c * floor((p + c * 0.5) / c) - c * 0.5;

    // Stepped rotation and sizing based on ID
    let h = hash31(id);
    let r1 = rot(h * PI * 2.0 + u.config.x * 0.5);
    p.x = p.x * r1[0].x + p.z * r1[0].y;
    p.z = p.x * r1[1].x + p.z * r1[1].y;

    // Create hopper crystal shape by subtracting smaller boxes
    let outer = sdBox(p, vec3<f32>(0.8));
    let inner1 = sdBox(p, vec3<f32>(0.6, 0.9, 0.6));
    let inner2 = sdBox(p, vec3<f32>(0.4, 1.0, 0.4));

    var d = max(outer, -inner1);
    d = max(d, -inner2);

    // Add some noise-based thickness variation
    d -= u.zoom_params.z * 0.1 * sin(p.x * 10.0) * sin(p.y * 10.0) * sin(p.z * 10.0);

    return vec2<f32>(d, h);
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.01, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));

    if (fragCoord.x >= res.x || fragCoord.y >= res.y) {
        return;
    }

    var uv = (fragCoord - 0.5 * res) / res.y;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -3.0 + u.config.x);
    let rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    // Raymarching
    var dO = 0.0;
    var dS = 0.0;
    var p = ro;
    var mat_id = 0.0;

    for(var i=0; i<MAX_STEPS; i++) {
        p = ro + rd * dO;
        let res = map(p);
        dS = res.x;
        mat_id = res.y;
        if(dS < SURF_DIST || dO > MAX_DIST) { break; }
        dO += dS;
    }

    var col = vec3<f32>(0.0);

    if(dO < MAX_DIST) {
        let n = getNormal(p);
        let v = -rd;

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 3.0);

        // Iridescent color mapping
        let t = dot(n, v) * 0.5 + 0.5 + mat_id * u.zoom_params.w;
        let albedo = palette(t);

        col = albedo * diff + albedo * fresnel;

        // Ambient occlusion approximation
        let ao = clamp(map(p + n * 0.1).x / 0.1, 0.0, 1.0);
        col *= ao;
    }

    // Fog
    col = mix(col, vec3<f32>(0.05, 0.02, 0.1), 1.0 - exp(-0.05 * dO));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)

Warp Radius (1.0, 0.1, 5.0, 0.1)
Warp Strength (2.0, 0.0, 10.0, 0.1)
Noise Amount (0.5, 0.0, 2.0, 0.1)
Color Shift (1.0, 0.1, 5.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "[YYYY-MM-DD]_[slug].md" "[Catchy Title]"
Reply with only: "✅ Plan created and queued: [YYYY-MM-DD]_[slug].md"
