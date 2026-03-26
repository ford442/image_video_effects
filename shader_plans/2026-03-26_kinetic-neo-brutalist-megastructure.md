# New Shader Plan: Kinetic Neo-Brutalist Megastructure

## Overview
An endlessly shifting, gravity-defying neo-brutalist megastructure of colossal floating concrete blocks that grind and interlock, revealing glowing, audio-reactive server cores hidden within.

## Features
- **Raymarched Brutalist Architecture:** Imposing, sharp-edged geometric monoliths dynamically carved using boolean SDF operations.
- **Audio-Reactive Shifts:** Massive blocks slide and reconfigure along grid axes driven by the audio beat accumulator (`u.config.y`).
- **Exposed Neon Cores:** Deep crevices between blocks glow with intense, pulsing neon volumetric light.
- **Domain Repetition & Warping:** Infinite, recursive architectural grids that distort subtly as they approach the event horizon.
- **Cinematic Lighting & Ambient Occlusion:** Soft shadows, heavy ambient occlusion, and neon reflections off rough concrete surfaces.
- **Mouse-Driven Gravity Well:** The mouse cursor acts as a localized gravity anomaly, pulling structures apart to reveal the inner network.

## Technical Implementation
- File: public/shaders/gen-kinetic-neo-brutalist-megastructure.wgsl
- Category: generative
- Tags: ["architecture", "cyberpunk", "mechanical", "audio-reactive", "raymarching", "SDF"]
- Algorithm: Raymarching with domain repetition, Box SDFs, Boolean subtractions, and audio-driven spatial translations.

### Core Algorithm
Uses a raymarching engine to render an infinite grid of brutalist structures via `opRep` (domain repetition) on a 3D grid. The primary geometry is composed of `sdBox` primitives modified by `opSubtract` to create windows, vents, and hollowed-out server bays. The position of each block is offset continuously using smooth stepped functions tied to `u.time` and quantized by `u.config.y` to snap to the beat.

### Mouse Interaction
The mouse (`u.mouse`) projects a 3D gravity sphere into the world. When structures fall within this sphere's radius, their local coordinates are pushed radially outward, simulating a kinetic parting of the megastructure to unveil the glowing core underneath.

### Color Mapping / Shading
Concrete surfaces use a desaturated, rough grey palette with high-frequency noise for texture. The internal cores emit highly saturated, overdriven neon colors (cyan, magenta, electric orange) mapped to a procedural emission function, creating striking contrast. Lighting is calculated using standard Phong shading combined with heavy, iterative ambient occlusion to give weight to the massive structures.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Kinetic Neo-Brutalist Megastructure
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    resolution: vec2<f32>,
    mouse: vec2<f32>,
    time: f32,
    config: vec4<f32>, // .y is audio beat accumulator
    zoom_params: vec4<f32>,
    custom_params: vec4<f32>,
};

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn hash13(p3: vec3<f32>) -> f32 {
    var p3_mod = fract(p3 * 0.1031);
    p3_mod += dot(p3_mod, p3_mod.yzx + 33.33);
    return fract((p3_mod.x + p3_mod.y) * p3_mod.z);
}

fn map(p: vec3<f32>) -> vec2<f32> {
    var pos = p;
    pos.x += sin(u.time * 0.5 + u.config.y) * 2.0;

    let spacing = 4.0;
    var cell = floor(pos / spacing);
    pos = pos - spacing * round(pos / spacing);

    var d = sdBox(pos, vec3<f32>(1.5, 1.8, 1.5));
    let d_sub = sdBox(pos, vec3<f32>(1.6, 0.5, 0.5));
    d = max(d, -d_sub);

    let mouse_pos = vec3<f32>((u.mouse * 2.0 - 1.0) * 10.0, 5.0);
    let dist_to_mouse = length(p - mouse_pos);
    if (dist_to_mouse < u.zoom_params.y) {
        d += (u.zoom_params.y - dist_to_mouse) * 0.5;
    }

    return vec2<f32>(d, hash13(cell));
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize( e.xyy*map( p + e.xyy ).x +
                      e.yyx*map( p + e.yyx ).x +
                      e.yxy*map( p + e.yxy ).x +
                      e.xxx*map( p + e.xxx ).x );
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let dims = textureDimensions(writeTexture);
    if (coords.x >= dims.x || coords.y >= dims.y) { return; }

    let uv = (vec2<f32>(coords) - 0.5 * vec2<f32>(dims)) / f32(dims.y);

    let ro = vec3<f32>(0.0, 0.0, -10.0 + u.time * u.zoom_params.w);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var mat_id = 0.0;
    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        if(res.x < 0.001 || t > 50.0) {
            mat_id = res.y;
            break;
        }
        t += res.x;
    }

    var col = vec3<f32>(0.01);
    if (t < 50.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let lig = normalize(vec3<f32>(0.8, 0.7, -0.6));
        let dif = clamp(dot(n, lig), 0.0, 1.0);

        var baseColor = vec3<f32>(0.3, 0.32, 0.35);
        let neon = vec3<f32>(0.0, 1.0, 0.8) * mat_id * (0.5 + 0.5 * sin(u.config.y * 10.0));

        col = baseColor * dif * u.zoom_params.x + neon * u.zoom_params.z;
        col = mix(col, vec3<f32>(0.05, 0.05, 0.08), 1.0 - exp(-0.02 * t * t));
    }

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Block Density (u.zoom_params.x) - (1.0, 0.1, 5.0, 0.1)
- Repulsion Radius (u.zoom_params.y) - (3.0, 0.0, 10.0, 0.1)
- Neon Intensity (u.zoom_params.z) - (1.0, 0.0, 5.0, 0.1)
- Travel Speed (u.zoom_params.w) - (1.0, 0.0, 5.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
