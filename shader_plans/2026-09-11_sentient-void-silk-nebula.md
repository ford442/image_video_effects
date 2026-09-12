# New Shader Plan: Sentient Void-Silk Nebula

## Overview
A hyper-dimensional fluid simulation that weaves iridescent "void silk" threads which organically react, tangle, and breathe with the environment.

## Features
- Deep volumetric fluid advection of a multi-scale vector field.
- Extruded, iridescent "silk" trails that map energy variations to structural metallic colors.
- Reactive gravity wells driven by acoustic low-end frequencies to bunch the threads together.
- Subsurface scattering simulation giving a highly organic, physical look to the microscopic threads.
- Non-euclidean folding allowing paths to visually loop and wrap in seamless hypnotic ways.
- A glowing plasma core at the center, drawing filaments towards it like a cosmic spindle.

## Technical Implementation
- File: public/shaders/gen-sentient-void-silk-nebula.wgsl
- Category: generative
- Tags: ["fluid", "organic", "threads", "iridescent", "subsurface"]
- Algorithm: Volumetric vector field traversal with advection trails and structural coloration.

### Core Algorithm
A 3D curl noise vector field acts as the fundamental driver. Instead of traditional raymarching or SDFs, we use particle simulation stored over time (via trailing feedback), or evaluate continuous curves procedurally based on advected coordinate spaces. The visual is built by blending advected noise patterns to simulate millions of microscopic, glowing silk threads stretching through the space.

### Mouse Interaction
The mouse acts as a localized phase shifter and attractor. As the mouse moves, the vector field locally diverges towards the pointer, pulling the glowing silk threads out of their standard paths to swirl around the cursor in a vortex-like magnetic attraction.

### Color Mapping / Shading
Uses structural coloration mapped via a phase-shifted cosine palette. As the tension (divergence) in the threads increases, the hue shifts dramatically towards bright neon purples, magentas, and cyan. Bloom is simulated using multi-scale mipmap blurring in post (implied by the visual language, although handled here by additive soft blending of dense thread bundles). A subtle dark rim shading on the threads gives a pseudo-subsurface feeling.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Sentient Void-Silk Nebula
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
  zoom_params: vec4<f32>,  // .x = Flow Speed, .y = Thread Density, .z = Vortex Strength, .w = Iridescence Shift
  ripples: array<vec4<f32>, 50>,
};

// --- Constants & Utilities ---
const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn palette(t: f32) -> vec3<f32> {
    return 0.5 + 0.5 * cos(TAU * (t + vec3<f32>(0.0, 0.33, 0.67)));
}

// 3D Curl Noise implementation placeholder
fn curlNoise(p: vec3<f32>) -> vec3<f32> {
    // Basic placeholder for curl noise to advect coordinates
    return vec3<f32>(sin(p.y), cos(p.z), sin(p.x));
}

@compute @workgroup_size(16, 16, 1)
fn computeMain(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = textureDimensions(readTexture);
    let coords = vec2<i32>(global_id.xy);
    if (coords.x >= i32(dimensions.x) || coords.y >= i32(dimensions.y)) { return; }

    let res = vec2<f32>(dimensions);
    let uv = (vec2<f32>(coords) / res) * 2.0 - 1.0;

    // Core parameters from UI
    let flowSpeed = u.zoom_params.x;
    let threadDensity = u.zoom_params.y;
    let vortexStrength = u.zoom_params.z;
    let iridescence = u.zoom_params.w;

    // Base 3D coordinate driven by time and uv
    let p = vec3<f32>(uv * 2.0, u.config.x * flowSpeed);

    // Interaction logic
    var divergence = p;
    if (u.zoom_config.w > 0.0) {
        let mouseDist = distance(uv, u.zoom_config.yz * 2.0 - 1.0);
        let pull = exp(-mouseDist * 4.0) * vortexStrength;
        divergence += pull * normalize(vec3<f32>(uv - (u.zoom_config.yz * 2.0 - 1.0), 0.0));
    }

    // Evaluate silk field
    let field = curlNoise(divergence * threadDensity);

    // Structural color
    let tension = length(field);
    let color = palette(tension * 0.5 + iridescence + u.config.x * 0.1);

    // Additive temporal blending
    let past = textureSampleLevel(readTexture, u_sampler, vec2<f32>(coords) / res, 0.0).rgb;
    let finalColor = mix(past, color * tension, 0.1);

    textureStore(writeTexture, coords, vec4<f32>(finalColor, 1.0));
}
```

Parameters (for UI sliders)

Flow Speed (0.5, 0.1, 2.0, 0.1)
Thread Density (1.0, 0.1, 5.0, 0.1)
Vortex Strength (1.0, 0.0, 3.0, 0.1)
Iridescence Shift (0.0, 0.0, 1.0, 0.05)
