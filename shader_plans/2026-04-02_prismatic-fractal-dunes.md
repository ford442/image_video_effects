# New Shader Plan: Prismatic Fractal-Dunes

## Overview
An infinite, shifting desert where the sand grains are micro-prisms, rippling and flowing like liquid glass under cosmic winds and erupting into chromatic geysers of light to the rhythm of sound.

## Features
- Infinite, sweeping desert landscape of shifting, refractive sand dunes driven by domain-warped FBM.
- Real-time chromatic dispersion and subsurface scattering as light filters through the prismatic sand.
- Audio-reactive geysers that erupt into floating, geometric crystal shards during bass peaks.
- Cosmic wind ribbons visualized by flowing, glowing plasma streams that trace the dune ridges.
- Dual-sun global illumination casting dynamic, shifting, and deeply saturated shadows.
- Interactive gravity manipulation allowing the mouse to carve craters and lift refractive sand pillars.

## Technical Implementation
- File: public/shaders/gen-prismatic-fractal-dunes.wgsl
- Category: generative
- Tags: ["landscape", "refraction", "audio-reactive", "raymarching", "fractal"]
- Algorithm: Raymarching against a complex heightmap generated via multi-octave FBM and domain warping, combined with KIFS for the erupting crystal shards.

### Core Algorithm
The dunes are formed using a raymarched terrain model where the SDF is an extruded 2D heightmap. The heightmap uses 6-octave domain-warped fractional Brownian motion (FBM) to simulate wind-swept sand ridges. The audio reactivity (`u.config.y`) controls the vertical displacement of the terrain and triggers the emergence of KIFS-based crystal shards from the dune peaks.

### Mouse Interaction
The user's mouse position (`u.zoom_config.y`, `u.zoom_config.z`) projects a gravitational singularity onto the 3D plane. This singularity carves a smooth-min crater into the terrain SDF and simultaneously pulls nearby crystal shards into a swirling vortex, controlled by distance to the projected coordinates.

### Color Mapping / Shading
The surface employs a highly complex Fresnel-based BRDF to simulate prismatic glass. Chromatic aberration is approximated by offset ray accumulation for red, green, and blue channels in the subsurface scattering phase. The crystal geysers glow with intense neon-cyan and magenta based on audio amplitude.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Prismatic Fractal-Dunes
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Dune Complexity, y=Prism Dispersion, z=Geyser Height, w=Wind Speed
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var mat = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var pp = p;
    for (var i = 0; i < octaves; i++) {
        v += a * noise(pp);
        pp = mat * pp * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    let uv = (fragCoord * 2.0 - res) / res.y;
    let time = u.config.x;
    let audio = u.config.y;

    // Parameters
    let duneComplexity = u.zoom_params.x;
    let dispersion = u.zoom_params.y;
    let geyserHeight = u.zoom_params.z;
    let windSpeed = u.zoom_params.w;

    // Output Base
    var col = vec3<f32>(0.05, 0.05, 0.1) * uv.y;

    // (Raymarching and Shading logic would go here)
    // Simplified stub to satisfy WGSL skeleton

    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
```

## UI Parameters
### Parameters (for UI sliders)

Name (default, min, max, step)
- Dune Complexity (5.0, 1.0, 10.0, 0.1)
- Prism Dispersion (1.5, 0.0, 5.0, 0.05)
- Geyser Height (2.0, 0.0, 5.0, 0.1)
- Wind Speed (1.0, 0.0, 3.0, 0.01)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-04-02_prismatic-fractal-dunes.md" "Prismatic Fractal-Dunes"
Reply with only: "✅ Plan created and queued: 2026-04-02_prismatic-fractal-dunes.md"