# New Shader Plan: Aetherial Chrono-Lattice

## Overview
A hyper-dimensional geometric framework where time and space crystallize into shifting, luminescent structures, reacting dynamically to the viewer's presence.

## Features
- Evolving 3D cellular automata-like structures.
- Prismatic refractive materials with chromatic dispersion.
- Fluid-like spatial distortion fields.
- Audio-reactive pulsing luminescence (using `plasmaBuffer`).
- Time-dilating vortex cores based on mouse interaction.
- Infinite domain repetition for a sense of endless scale.

## Technical Implementation
- File: public/shaders/gen-aetherial-chrono-lattice.wgsl
- Category: generative
- Tags: ["geometric", "crystal", "abstract", "audio-reactive", "interactive"]
- Algorithm: Raymarching infinite domains with audio-reactive materials and spatial distortion

### Core Algorithm
Raymarching an SDF composed of endlessly repeating, intricately faceted geometries (like a 3D Voronoi or crystalline lattice). The domain repetition will be modulated by low-frequency noise. The SDF shapes will morph over time based on `u.config.x`.

### Mouse Interaction
When the mouse is clicked (`u.zoom_config.w > 0.5`), the geometry within a radius of `u.zoom_config.yz` will be severely twisted around a gravity well. This spatial distortion formula applies a rotational matrix inversely proportional to the distance to the mouse cursor.

### Color Mapping / Shading
Materials will use a base chromatic gradient shifted by the depth and normal data. Highlights will be boosted by audio inputs extracted from `plasmaBuffer[0]` (e.g., bass for intensity, treble for color shifting). A soft bloom effect and subsurface scattering approximation will add a luminescent, ethereal quality.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Aetherial Chrono-Lattice
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

const MAX_STEPS = 100;
const MAX_DIST = 100.0;
const SURF_DIST = 0.001;

fn rot2d(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdf(p: vec3<f32>) -> f32 {
    var p_mod = p;
    let t = u.config.x * u.zoom_params.x;

    if (u.zoom_config.w > 0.5) {
        let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 10.0, (u.zoom_config.z - 0.5) * -10.0, 5.0);
        let d_mouse = length(p.xy - mouse_pos.xy);
        let twist = smoothstep(5.0, 0.0, d_mouse) * 3.14159;
        p_mod.x = p_mod.x * cos(twist) - p_mod.y * sin(twist);
        p_mod.y = p_mod.x * sin(twist) + p_mod.y * cos(twist);
    }

    p_mod.x = (fract(p_mod.x / 4.0 + 0.5) - 0.5) * 4.0;
    p_mod.y = (fract(p_mod.y / 4.0 + 0.5) - 0.5) * 4.0;
    p_mod.z = (fract(p_mod.z / 4.0 + 0.5) - 0.5) * 4.0;

    let sphere = length(p_mod) - (1.0 + sin(t + p.x)*0.2) * u.zoom_params.y;

    let box = length(max(abs(p_mod) - vec3<f32>(0.8), vec3<f32>(0.0)));
    return mix(sphere, box, 0.5 + 0.5*sin(t*0.5));
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let d = sdf(p);
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(sdf(p - e.xyy), sdf(p - e.yxy), sdf(p - e.yyx));
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(global_id.x), f32(global_id.y));
    if (fragCoord.x >= resolution.x || fragCoord.y >= resolution.y) { return; }

    var uv = (fragCoord - 0.5 * resolution) / resolution.y;

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0) * u.zoom_params.w;
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0) * u.zoom_params.w;

    let ro = vec3<f32>(0.0, 0.0, -5.0 + u.config.x * 2.0);
    var rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    rd.x = rd.x * cos(u.config.x*0.1) - rd.y * sin(u.config.x*0.1);
    rd.y = rd.x * sin(u.config.x*0.1) + rd.y * cos(u.config.x*0.1);

    var dO = 0.0;
    var p = ro;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * dO;
        let dS = sdf(p);
        dO += dS;
        if (dO > MAX_DIST || dS < SURF_DIST) { break; }
    }

    var col = vec3<f32>(0.0);

    if (dO < MAX_DIST) {
        let n = getNormal(p);
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);

        let colorShift = u.zoom_params.z;
        let baseCol = 0.5 + 0.5 * cos(u.config.x + p.xyz * 0.5 + vec3<f32>(0.0, 2.0, 4.0) + colorShift);

        col = baseCol * diff;

        col += vec3<f32>(bass * 0.5, 0.0, treble * 0.5) * pow(1.0 - diff, 3.0);

        let fog = 1.0 - exp(-0.02 * dO);
        col = mix(col, vec3<f32>(0.05, 0.05, 0.1), fog);
    } else {
        col = vec3<f32>(0.02, 0.02, 0.05) + bass * 0.1;
    }

    col = pow(col, vec3<f32>(1.0 / 2.2));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)

Morph Speed (1.0, 0.1, 5.0, 0.1)
Fractal Detail (0.5, 0.0, 1.0, 0.01)
Color Shift (0.0, 0.0, 1.0, 0.01)
Audio Reactivity (1.0, 0.0, 2.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
