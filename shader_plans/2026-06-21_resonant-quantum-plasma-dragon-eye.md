# New Shader Plan: Resonant Quantum-Plasma Dragon-Eye

## Overview
A hyper-dimensional, endlessly morphing cosmic dragon's eye forged from swirling quantum plasma and fractal dark matter, its pupil dilating and glowing violently in response to deep acoustic bass frequencies.

## Features
- Colossal, multi-layered reptilian iris using twisted fractal noise and liquid neon gradients.
- Slit pupil that actively dilates, snaps, and contorts in real-time syncing to audio beats.
- Dense volumetric quantum plasma atmosphere bleeding from the edges of the eye into the void.
- Subsurface scattering effect on the bioluminescent scales surrounding the eye socket.
- Highly reactive audio-driven chromatic aberration rippling through the vitreous fluid.
- Deep, parallax-rich internal lighting mimicking a contained supernova behind the pupil.
- Mouse interaction that acts as a focal point, drawing the dragon's intense gaze.

## Technical Implementation
- File: public/shaders/gen-resonant-quantum-plasma-dragon-eye.wgsl
- Category: generative
- Tags: ["organic", "quantum", "cosmic", "fractal", "audio-reactive"]
- Algorithm: Raymarching through layered Torus and Sphere SDFs with heavy domain distortion for the iris, combined with volumetric plasma noise.

### Core Algorithm
Raymarching is employed to render a complex intersection of sphere and distorted toroidal SDFs forming the eye structure. The iris uses a custom polar-coordinate fractal noise function to create the intricate, fibrous muscular patterns of a reptilian eye. The pupil is an inverted cylinder SDF whose radius is tightly bound to `u.config.y` (audio/click), creating an aggressive dilation effect.

### Mouse Interaction
The eye structure rotates to "look" at the mouse coordinates mapped from `u.zoom_config.y` and `u.zoom_config.z`. The mouse also acts as a gravitational lens, applying a slight spatial distortion (using a smoothstep falloff) to the light rays entering the eye, mimicking the bending of light by a massive cosmic entity.

### Color Mapping / Shading
The color palette uses intense liquid-neon greens, piercing golds, and deep abyss blues. The shading utilizes a custom subsurface scattering approximation for the iris fibers, combined with a heavy bloom and chromatic aberration pass driven by `u.zoom_params.w` to simulate the dense, glowing plasma environment.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Resonant Quantum-Plasma Dragon-Eye
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Plasma Density, y=Iris Complexity, z=Pupil Sharpness, w=Aberration
    ripples: array<vec4<f32>, 50>,
};

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

const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

// 2D Rotation Matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Main SDF
fn map(p: vec3<f32>) -> f32 {
    // ... complex SDF combining sphere and toroids
    return length(p) - 1.0;
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> f32 {
    var dO: f32 = 0.0;
    for(var i: i32 = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let dS = map(p);
        dO += dS;
        if(dO > MAX_DIST || dS < SURF_DIST) { break; }
    }
    return dO;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<f32>(f32(id.x), f32(id.y));

    if (coord.x >= dimensions.x || coord.y >= dimensions.y) {
        return;
    }

    let uv = (coord - 0.5 * dimensions) / dimensions.y;
    // ... color calculation and raymarching

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(0.0, 0.0, 0.0, 1.0));
}
```

Parameters (for UI sliders)

- Plasma Density (0.5, 0.0, 1.0, 0.01) - mapped to u.zoom_params.x
- Iris Complexity (1.0, 0.1, 5.0, 0.1) - mapped to u.zoom_params.y
- Pupil Sharpness (0.8, 0.1, 2.0, 0.01) - mapped to u.zoom_params.z
- Aberration (0.1, 0.0, 1.0, 0.01) - mapped to u.zoom_params.w

Integration Steps

1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
