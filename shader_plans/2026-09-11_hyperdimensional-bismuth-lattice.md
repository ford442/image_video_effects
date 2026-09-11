# New Shader Plan: Hyperdimensional Bismuth Lattice

## Overview
A crystalline, non-euclidean descent through shifting bismuth-like hopper crystals that iridescently react to sound frequencies. The aesthetic is angular, highly metallic, geometrically paradoxical, and bursting with thin-film interference gradients that give it an alien, high-tech geological vibe.

## Features
- Infinite raymarched fractal descent through folding orthogonal geometry.
- Dynamic hopper-crystal structures (like bismuth) generated via iterated domain folding and box SDFs.
- Intense thin-film interference chromatic shading that shifts with view angle and depth.
- Audio-reactive crystal growth: bass pulses expand the geometry, treble creates sharp structural glitches.
- Mouse interaction acts as a localized gravity/folding well, twisting the orthogonal space into spirals.
- Metallic lighting with ambient occlusion and harsh specular highlights for a polished, hyper-real look.
- Fast, smooth temporal anti-aliasing blending over frames.

## Technical Implementation
- File: public/shaders/gen-hyperdimensional-bismuth-lattice.wgsl
- Category: generative
- Tags: ["generative", "fractal", "raymarch", "metallic", "iridescent", "bismuth", "crystal", "audio-reactive"]
- Algorithm: Raymarching through a folded space field using repeated and mirrored Box Signed Distance Fields (SDFs) to create fractal hopper-crystals.

### Core Algorithm
The environment is formed by raymarching a fractal SDF. The base shape is a hollow or stepped box. Space is repeatedly folded using `abs(p)` and rotated by constant matrices to create self-similar, nested 90-degree stair-step structures characteristic of bismuth. The iteration count and scaling factor per fold determine the complexity. Distance estimators are modified by low-frequency time to shift the fractal seed.

### Mouse Interaction
The mouse cursor introduces a localized spatial twist before the SDF evaluation. By taking the distance from the projected ray position to the mouse axis in screen-space, space is rotated on the XY plane proportionally to the inverse of the distance, creating a vortex-like warping of the otherwise rigid orthogonal structures.

### Color Mapping / Shading
The coloring relies heavily on the surface normal and view direction (N dot V). This value is used to sample a continuous cosine gradient palette specifically tuned to mimic thin-film interference (vivid pinks, greens, golds, and blues). A sharp specular component (Phong/Blinn-Phong) adds metallic sheen, and an iterative ambient occlusion (AO) step deepens the crevices of the stepped structures.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Hyperdimensional Bismuth Lattice
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
  zoom_params: vec4<f32>,  // .x = Complexity, .y = Iridescence, .z = Twist, .w = Speed
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 50.0;

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Box SDF
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// Fractal folding space
fn map(p: vec3<f32>) -> f32 {
    var pos = p;
    // Mouse twist
    let twist = u.zoom_params.z;
    if (twist > 0.0) {
        let mouse = u.zoom_config.yz;
        // Simplified twist for structure outline
        let r = length(pos.xy - (mouse * 2.0 - 1.0) * 5.0);
        let a = twist * exp(-r * 0.5);
        let rt = rot(a);
        pos.x = pos.x * rt[0][0] + pos.y * rt[1][0];
        pos.y = pos.x * rt[0][1] + pos.y * rt[1][1];
    }

    // Fractal iterations
    let iters = 4.0 + (u.zoom_params.x * 4.0);
    var scale = 1.0;

    // Simple placeholder for bismuth-like folding
    for (var i = 0; i < 4; i++) {
        if (f32(i) > iters) { break; }
        pos = abs(pos) - vec3<f32>(0.5);

        let ry = rot(PI / 4.0);
        pos.x = pos.x * ry[0][0] + pos.z * ry[1][0];
        pos.z = pos.x * ry[0][1] + pos.z * ry[1][1];

        let rz = rot(PI / 4.0);
        pos.x = pos.x * rz[0][0] + pos.y * rz[1][0];
        pos.y = pos.x * rz[0][1] + pos.y * rz[1][1];

        pos = pos * 2.0;
        scale = scale * 2.0;
    }

    return sdBox(pos, vec3<f32>(0.5)) / scale;
}

// Main Compute Shader Outline
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // Basic setup, screen coords, ray origin, ray direction
    // Raymarch loop
    // Normal calculation
    // Iridescent coloring based on normal, view direction, and depth
    // Output to writeTexture
}
```

## Parameters (for UI sliders)
- Complexity (0.5, 0.0, 1.0, 0.01) - Maps to zoom_params.x - Controls the number of fractal folding iterations.
- Iridescence (0.5, 0.0, 1.0, 0.01) - Maps to zoom_params.y - Shifts the phase of the thin-film interference palette.
- Twist (0.5, 0.0, 1.0, 0.01) - Maps to zoom_params.z - Strength of the spatial warping around the mouse cursor.
- Speed (0.5, 0.0, 1.0, 0.01) - Maps to zoom_params.w - Speed of the forward camera descent and fractal shifting.
