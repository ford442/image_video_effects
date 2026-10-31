# New Shader Plan: Stellar Cyber-Lotus Forge

## Overview
A colossal biomechanical lotus blooming in deep space, its petals woven from pulsing neon plasma and celestial dust.

## Features
- Intricate, multi-layered lotus geometry generated via polar SDF folding and smooth minimums.
- Dynamic plasma-flow energy veins running through the petals, animated by time and audio reactivity.
- Ambient celestial dust particles floating around the central core.
- Audio-reactive bloom intensity and core rotation speed based on `plasmaBuffer[0]` (bass, mids, treble).
- Mouse interaction: clicking and dragging creates a gravitational distortion field that warps the lotus petals toward the cursor.
- Iridescent, cyberpunk color mapping: deep void blues transitioning to electric magenta and liquid gold.

## Technical Implementation
- File: public/shaders/gen-stellar-cyber-lotus-forge.wgsl
- Category: generative
- Tags: ["organic", "cyberpunk", "cosmic", "audio-reactive", "interactive"]
- Algorithm: Volumetric raymarching with polar repetition and domain distortion.

### Core Algorithm
The shader will use raymarching to render the geometry. The core shape is built using a base sphere (the core) and multiple folded planes/boxes distorted by sine waves to form the petals. Polar repetition (`atan2`) will be used to array the petals around the center. Smooth minimums (`smin`) will blend the petals into the core. A noise function (e.g., fbm or simplex) will displace the surface to create the biomechanical texture and plasma veins.

### Mouse Interaction
When the mouse is clicked (`u.zoom_config.w > 0.5`), a localized spherical distortion will be applied to the raymarching domain (`p`). The strength of the distortion will be inversely proportional to the distance between `p` and the mapped mouse position (`u.zoom_config.yz`). This will create a gravity well effect that bends the petals toward the cursor.

### Color Mapping / Shading
The shading will use a mix of ambient occlusion (estimated from SDF steps) and fake subsurface scattering. The base color will transition from deep blue in the crevices to bright magenta at the tips. The energy veins will glow with liquid gold, modulated by `plasmaBuffer[0].x` (bass) for pulsing intensity. A bloom pass (simulated via accumulated glow along the ray) will enhance the neon look.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Stellar Cyber-Lotus Forge
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

const PI = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;

    // Mouse Interaction: Gravity well when clicked
    if (u.zoom_config.w > 0.5) {
        let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (0.5 - u.zoom_config.z) * 5.0, 0.0);
        let dist_to_mouse = length(p - mouse_pos);
        if (dist_to_mouse < 3.0) {
            let pull = 1.0 - smoothstep(0.0, 3.0, dist_to_mouse);
            p = mix(p, mouse_pos, pull * 0.5);
        }
    }

    let time = u.config.x * u.zoom_params.y; // Rotation Speed

    // Rotate entire lotus
    let xz = rot(time * 0.2) * vec2<f32>(p.x, p.z);
    p.x = xz.x;
    p.z = xz.y;

    // Core sphere
    let core = length(p) - 1.0;

    // Petals (Polar repetition)
    var d = 100.0;
    let num_petals = u.zoom_params.z; // Petal Complexity
    for (var i = 0.0; i < 6.0; i = i + 1.0) { // Max petals, break early if needed based on num_petals, simplified here for structure
        let angle = (i / 6.0) * PI * 2.0;
        var pp = p;
        let xz_petal = rot(angle) * vec2<f32>(pp.x, pp.z);
        pp.x = xz_petal.x;
        pp.z = xz_petal.y;

        pp.x -= 1.2; // Offset from center

        // Fold/Curve the petal
        pp.y -= sin(pp.x * 2.0 + time) * 0.3;

        let petal = length(vec3<f32>(pp.x, max(0.0, abs(pp.y) - 0.05), pp.z)) - 0.5 + p.x * 0.2; // Tapering box-like shape
        d = smin(d, petal, 0.4);
    }

    return smin(core, d, 0.5);
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) - 0.5 * resolution) / resolution.y;

    // Ray setup
    let ro = vec3<f32>(0.0, 2.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var p = ro;
    var t = 0.0;
    var glow = 0.0;

    // Raymarching
    for (var i = 0; i < 64; i++) {
        p = ro + rd * t;
        let d = map(p);

        if (d < 0.01) { break; }
        if (t > 15.0) { break; }

        glow += 0.05 / (0.1 + d); // Simple bloom accumulation
        t += d * 0.8;
    }

    // Audio reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let bloom_intensity = u.zoom_params.x * (1.0 + bass * 2.0); // Bloom Intensity

    // Coloring
    var col = vec3<f32>(0.0);
    if (t < 15.0) {
        let baseColor = mix(vec3<f32>(0.1, 0.2, 0.5), vec3<f32>(0.8, 0.1, 0.6), clamp(length(p)*0.3, 0.0, 1.0));
        let veinGlow = vec3<f32>(1.0, 0.8, 0.2) * glow * 0.02 * u.zoom_params.w * (1.0 + bass); // Vein Glow
        col = baseColor + veinGlow;
    }

    col += vec3<f32>(0.2, 0.5, 0.8) * glow * 0.01 * bloom_intensity; // Ambient bloom

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
```
Parameters (for UI sliders)

Bloom Intensity (0.5, 0.0, 1.0, 0.01)
Rotation Speed (1.0, 0.0, 5.0, 0.1)
Petal Complexity (3.0, 1.0, 6.0, 1.0)
Vein Glow (0.8, 0.0, 2.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
