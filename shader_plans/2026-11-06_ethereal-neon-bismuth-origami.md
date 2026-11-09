# New Shader Plan: Ethereal Neon-Bismuth Origami

## Overview
A hyper-dimensional realm where geometric crystal shards, reminiscent of bismuth hopper crystals, continuously fold and unfold like ethereal neon origami floating in a dark expanse.

## Features
- **Fractal Origami Folding**: Distance fields constructed from repeating, rotating planes that intersect to form hopper-crystal geometries.
- **Dynamic Unfolding**: The geometry expands and contracts smoothly using harmonic temporal domain wrapping.
- **Prismatic Neon Iridescence**: A sophisticated shading model simulating thin-film interference, generating vibrant, shifting bismuth-like colors on the crystalline edges.
- **Volumetric Neon Core**: The center of the structure emits a glowing volumetric aura achieved through progressive density accumulation during raymarching.
- **Glass Refraction Illusion**: Modulated surface normals create the illusion of translucent crystal layers refracting inner geometry.

## Technical Implementation
- File: public/shaders/gen-ethereal-neon-bismuth-origami.wgsl
- Category: generative
- Tags: ["origami", "bismuth", "fractal", "iridescent", "neon", "crystal"]
- Algorithm: Raymarching a combination of recursive space-folding and intersection of infinite planes to form intricate crystalline structures, with thin-film interference coloring based on surface normals and viewing angles.

### Core Algorithm
The core of the SDF utilizes a recursive space-folding technique (similar to KIFS - Kaleidoscopic Iterated Function Systems) combined with absolute value folding. This creates the intricate, self-repeating 90-degree step structures seen in bismuth crystals. Time modulates the rotation and translation matrices within the iteration loop, causing the "origami" to dynamically fold and unfold.

### Mouse Interaction
The mouse (`u.zoom_config.yz`) acts as a point of gravitational and structural attraction. Its coordinates are mapped to 3D space, and distance from this point smoothly modulates the scaling factor and rotation speed of the KIFS fractals. Bringing the mouse close causes the structure to rapidly unfold and bloom outward, while moving away allows it to settle back into a tighter, crystalline box.

### Color Mapping / Shading
The shading model calculates the angle between the surface normal and the view direction. This angle, combined with the distance from the fractal core, indexes into a fast cosine-based palette to simulate the iridescent spectrum of bismuth (blues, purples, golds, and pinks). The edges of the geometry are highlighted with intense neon emission, and a soft glow is added by accumulating inverse distance during the raymarching loop.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Ethereal Neon-Bismuth Origami
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
// Shader Code
// ----------------------------------------------------------------

// 2D Rotation Matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Bismuth/Iridescent Color Palette based on Cosine Gradients
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.3, 0.20, 0.20);
    return a + b * cos(6.28318 * (c * t + d));
}

// Kaleidoscopic Iterated Function System (KIFS) for Bismuth geometry
fn map(p_in: vec3<f32>, time: f32, mouse_pos: vec3<f32>) -> f32 {
    var p = p_in;

    // Mouse Interaction: Bloom effect
    let dist_to_mouse = length(p - mouse_pos);
    let bloom_factor = smoothstep(2.0, 0.0, dist_to_mouse) * u.zoom_params.y; // u.zoom_params.y is Bloom Strength

    let scale = 1.2 + sin(time * 0.5) * 0.1 + bloom_factor * 0.5;

    var d = 100.0;

    // Iterative space folding
    for (var i = 0; i < 4; i = i + 1) {
        // Fold 1
        p = abs(p) - vec3<f32>(1.0, 1.0, 1.0) * u.zoom_params.x; // u.zoom_params.x is Scale

        // Rotate
        p.x = p.x * cos(time * 0.2) - p.y * sin(time * 0.2);
        p.y = p.x * sin(time * 0.2) + p.y * cos(time * 0.2);

        p.y = p.y * cos(time * 0.3) - p.z * sin(time * 0.3);
        p.z = p.y * sin(time * 0.3) + p.z * cos(time * 0.3);

        // Scale
        p = p * scale;

        // Cube SDF
        let q = abs(p) - vec3<f32>(0.5);
        let current_d = length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);

        // Min distance, scaled back
        d = min(d, current_d * pow(scale, f32(-i - 1)));
    }

    return d;
}

// Calculate normal using finite differences
fn getNormal(p: vec3<f32>, time: f32, mouse_pos: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, mouse_pos) - map(p - e.xyy, time, mouse_pos),
        map(p + e.yxy, time, mouse_pos) - map(p - e.yxy, time, mouse_pos),
        map(p + e.yyx, time, mouse_pos) - map(p - e.yyx, time, mouse_pos)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    // Normalized coordinates (-1 to 1)
    let uv = (vec2<f32>(id.xy) - 0.5 * resolution) / resolution.y;

    let time = u.config.x * u.zoom_params.w; // u.zoom_params.w is Time Speed

    // Mouse coordinates mapped to 3D space
    var mouse_uv = u.zoom_config.yz;
    if (u.zoom_config.w < 0.5) {
        // Default to center if mouse not pressed
        mouse_uv = vec2<f32>(0.5, 0.5);
    }
    let mouse_pos = vec3<f32>((mouse_uv - 0.5) * 4.0, 0.0);

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -3.0); // Ray origin (camera)
    let rd = normalize(vec3<f32>(uv, 1.0)); // Ray direction

    var p = ro;
    var t = 0.0;
    var i = 0.0;
    var glow = 0.0;

    // Raymarching loop
    for (i = 0.0; i < 100.0; i = i + 1.0) {
        let d = map(p, time, mouse_pos);
        if (d < 0.001 || t > 10.0) {
            break;
        }
        t = t + d;
        p = ro + rd * t;

        // Volumetric glow accumulation
        glow = glow + 0.02 / (0.1 + d);
    }

    var col = vec3<f32>(0.0);

    if (t < 10.0) {
        // We hit the surface
        let n = getNormal(p, time, mouse_pos);

        // Lighting
        let light_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light_dir), 0.0);
        let view_dir = normalize(ro - p);

        // Thin-film interference (iridescence) based on viewing angle
        let fresnel = 1.0 - max(dot(n, view_dir), 0.0);
        col = palette(fresnel * u.zoom_params.z + time * 0.1); // u.zoom_params.z is Iridescence Rate

        col = col * (diff * 0.8 + 0.2); // Apply diffuse lighting

        // Edge highlighting (neon effect)
        let edge = smoothstep(0.4, 0.5, fract(p.x * 5.0)) + smoothstep(0.4, 0.5, fract(p.y * 5.0));
        col = col + vec3<f32>(0.2, 0.8, 1.0) * edge * 0.5;

    }

    // Add volumetric glow
    col = col + vec3<f32>(0.8, 0.2, 0.9) * glow * 0.05;

    // Gamma correction
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}
```

## Parameters (for UI sliders)
- **Scale** (default: 0.5, min: 0.1, max: 2.0, step: 0.01) - Initial spacing of the fractal folds (mapped to `u.zoom_params.x`)
- **Bloom Strength** (default: 1.0, min: 0.0, max: 3.0, step: 0.1) - The intensity of the unfolding effect when the mouse is near (mapped to `u.zoom_params.y`)
- **Iridescence Rate** (default: 2.0, min: 0.5, max: 5.0, step: 0.1) - How rapidly the colors cycle across the viewing angles (mapped to `u.zoom_params.z`)
- **Time Speed** (default: 1.0, min: 0.1, max: 3.0, step: 0.1) - The overall animation speed (mapped to `u.zoom_params.w`)

## Integration Steps
1. Create shader file `public/shaders/gen-ethereal-neon-bismuth-origami.wgsl`
2. Create JSON definition `shader_definitions/ethereal-neon-bismuth-origami.json`
3. Run `node scripts/buildMultipassRegistry.js && node scripts/generate_shader_lists.js && node scripts/generate-shader-definition-types.mjs`
4. Upload via `python3 tools/deploy/sync_shaders_to_storage.py` (dry-run first)
