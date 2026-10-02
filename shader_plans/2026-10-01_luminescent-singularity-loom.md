# New Shader Plan: Luminescent Singularity Loom

## Overview
A cosmic-organic loom weaving ethereal, glowing threads around a central gravitational singularity that pulses and distorts spacetime.

## Features
- Gravitational lens distortion around a central void (singularity).
- Organic, bioluminescent fractal threads generated via domain warping and 3D noise.
- Mouse interaction: Attracts threads and warps the singularity, shifting its gravity well.
- Subsurface scattering simulation for a translucent, "fleshy" cosmic feel.
- Multi-colored temporal trails with decay and smooth HDR bloom.
- Pulse and rotation driven by underlying audio/rhythmic mechanics (if extraBuffer supports it, or simply time-based).
- Depth-based atmospheric scattering (fog) blending the loom into the void.

## Technical Implementation
- File: public/shaders/gen-luminescent-singularity-loom.wgsl
- Category: generative
- Tags: ["organic", "cosmic", "fractal", "singularity", "loom", "glow", "3d"]
- Algorithm: Raymarching an organic volumetric structure with gravitational distortion, using FBM (Fractional Brownian Motion) for domain warping and iterative threading patterns.

### Core Algorithm
- Raymarching a signed distance field (SDF).
- The central object is a sphere (singularity) with a negative distance or extreme smoothing, combined with an outer shell of fractal lines.
- The space itself is deformed (domain warping) using `sin`/`cos` and 3D noise (FBM) to create the "threads".
- Particles/threads follow paths modeled as swirling vortexes, using `q.xy *= rot2D(time + distance)`.

### Mouse Interaction
- `zoom_config.w > 0.0` triggers active interaction.
- The mouse position (`zoom_config.yz`) shifts the center of the singularity and applies an intense local gravitational pull (vortex distortion) to the threads.
- Pull strength increases as distance to mouse UV decreases.

### Color Mapping / Shading
- A base color of deep void blue/purple (e.g., `vec3(0.05, 0.0, 0.1)`).
- Luminescent threads use a cosine palette mapped to density and distance, shifting from electric blue to magenta to hot orange.
- Fake subsurface scattering by sampling the SDF inside the geometry (stepping slightly along the normal) and injecting warm light.
- Smooth bloom achieved via temporal accumulation and HDR tonemapping (ACES).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Luminescent Singularity Loom
// Category: generative
// ----------------------------------------------------------------

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
  zoom_params: vec4<f32>,  // .x = Thread Density, .y = Loom Speed, .z = Glow Intensity, .w = Color Shift
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// Helper: 2D Rotation
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Helper: Palette
fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557); // Shift this based on zoom_params.w
    return a + b * cos(TAU * (c * t + d));
}

// Map function (SDF)
fn map(p: vec3<f32>) -> f32 {
    // Loom distortion
    var q = p;
    let time = u.config.x * u.zoom_params.y;

    // Mouse Interaction: Gravity Well
    if (u.zoom_config.w > 0.0) {
        let mouse_pos = vec2<f32>(u.zoom_config.y - 0.5, (1.0 - u.zoom_config.z) - 0.5) * 5.0; // rough mapping
        let dist = length(q.xy - mouse_pos);
        let pull = exp(-dist * 2.0);

        let qxy = q.xy - mouse_pos * pull;
        q = vec3<f32>(qxy, q.z);
    }

    // Space folding
    let rot = rot2D(time * 0.2 + length(q) * 0.5);
    let qxz = q.xz * rot;
    q = vec3<f32>(qxz.x, q.y, qxz.y);

    // Threads (fractal cylinders)
    var d = 100.0;
    let density = u.zoom_params.x * 2.0 + 1.0;

    for (var i = 0; i < 4; i++) {
        let fi = f32(i);
        q = abs(q) - vec3<f32>(0.5, 0.5, 0.5) * density;
        let qr = q.xy * rot2D(time * 0.1 + fi);
        q = vec3<f32>(qr, q.z);
        let cyl = length(q.xy) - 0.05 * (fi + 1.0);
        d = min(d, cyl);
    }

    // Central Singularity
    let sphere = length(p) - 0.8;

    // Combine with smooth minimum
    let k = 0.5;
    let h = clamp(0.5 + 0.5 * (sphere - d) / k, 0.0, 1.0);
    return mix(sphere, d, h) - k * h * (1.0 - h);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // ... compute implementation ...
}
```

## Parameters (for UI sliders)

Name (default, min, max, step)
- Thread Density (0.5, 0.0, 1.0, 0.01) -> zoom_params.x
- Loom Speed (0.5, 0.0, 1.0, 0.01) -> zoom_params.y
- Glow Intensity (0.5, 0.0, 1.0, 0.01) -> zoom_params.z
- Color Shift (0.0, 0.0, 1.0, 0.01) -> zoom_params.w

## Integration Steps

1. Create shader file `public/shaders/gen-luminescent-singularity-loom.wgsl`
2. Create JSON definition `shader_definitions/generative/gen-luminescent-singularity-loom.json`
3. Run `node scripts/generate_shader_lists.js`
4. Upload via `python scripts/sync_shaders_to_storage.py --force`
