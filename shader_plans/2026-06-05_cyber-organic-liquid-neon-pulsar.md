# New Shader Plan: Cyber-Organic Liquid-Neon Pulsar

## Overview
A biomechanical, pulsating celestial core composed of hyper-viscous liquid-neon and crystalline techno-organic fibers that rhythmically contract, dilate, and emit intense volumetric light bursts in sync with deep acoustic resonance.

## Features
- Real-time fluidic displacement mapped onto a hyper-dense spherical core.
- Audio-reactive volumetric light rays (god rays) erupting from the pulsar's core.
- Biomechanical metallic fibers that weave and unweave using intricate Voronoi structures.
- Prismatic color shifting driven by time, spatial coordinates, and simulated depth.
- Mouse-interactive gravity well that distorts the fiber structure and pulls the liquid-neon towards the cursor.

## Technical Implementation
- File: public/shaders/gen-cyber-organic-liquid-neon-pulsar.wgsl
- Category: generative
- Tags: ["biomechanical", "neon", "pulsar", "volumetric", "liquid", "audio-reactive"]
- Algorithm: Raymarching combined with domain repetition, fBM (Fractional Brownian Motion), and audio-modulated smooth minimums for the techno-organic aesthetic.

### Core Algorithm
- Use raymarching to render the primary spherical pulsar core.
- Apply 3D fBM noise layered with Voronoi cellular noise to displace the sphere's surface, creating the biomechanical fiber look.
- Use a smooth minimum (`smin`) to blend the metallic fibers with the underlying glowing liquid-neon base.
- Implement volumetric scattering by accumulating glow along the ray steps based on distance to the core and audio amplitude.

### Mouse Interaction
- Calculate the distance from the screen-space pixel coordinate to the normalized mouse position `vec2(u.zoom_config.y, u.zoom_config.z)`.
- Apply a spatial distortion: `p.xy += normalize(mouse_dir) * smoothstep(0.5, 0.0, mouse_dist) * 0.2;`
- This creates an intense gravity-well effect, pulling and stretching the metallic fibers towards the cursor.

### Color Mapping / Shading
- Liquid-neon core: Iridescent palette cycling through cyan, magenta, and electric blue (`cos` palette based on normal and time).
- Metallic fibers: High specularity, dark base color with intense rim lighting.
- Bloom/Glow: Accumulated density from raymarching mapped to a highly saturated neon emission gradient, modulated by `u.config.y` (audio/pulse).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Cyber-Organic Liquid-Neon Pulsar
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
    ripples: array<vec4<f32>, 50>,
};

// ... Helper functions (hash, noise, smin, rotation) ...

// Core SDF for the pulsar
fn map(p: vec3<f32>, time: f32, audio: f32) -> f32 {
    // Basic sphere
    var d = length(p) - 1.0;

    // Biomechanical displacement
    let disp = fbm(p * 2.5 + time * 0.2);

    // Audio pulsation
    let pulse = audio * 0.1 * sin(time * 5.0);

    return d + disp * 0.3 + pulse;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    let coords = vec2<i32>(id.xy);

    if (coords.x >= i32(dimensions.x) || coords.y >= i32(dimensions.y)) {
        return;
    }

    let uv = (vec2<f32>(coords) - 0.5 * vec2<f32>(dimensions)) / f32(dimensions.y);
    let time = u.config.x;
    let audio = u.config.y;

    // ... Raymarching loop ...

    // ... Coloring and volumetric accumulation ...

    // ... Output to writeTexture ...
}
```

## Parameters (for UI sliders)
- `param1` (Base Color Hue, default: 0.5, min: 0.0, max: 1.0, step: 0.01)
- `param2` (Fiber Density, default: 2.5, min: 0.5, max: 5.0, step: 0.1)
- `param3` (Pulsation Speed, default: 1.0, min: 0.1, max: 3.0, step: 0.1)
- `param4` (Glow Intensity, default: 1.5, min: 0.0, max: 3.0, step: 0.1)

## Integration Steps
1. Create shader file `public/shaders/gen-cyber-organic-liquid-neon-pulsar.wgsl`
2. Create JSON definition `shader_definitions/generative/gen-cyber-organic-liquid-neon-pulsar.json`
3. Run `node scripts/generate_shader_lists.js`
4. Upload via `storage_manager`