# New Shader Plan: Cyber-Organic Void-Mycelium Pulsar

## Overview
A hyper-intricate cybernetic fungal network expanding endlessly through an abyssal void, pulsating with neon bioluminescence and audio-reactive quantum spores.

## Features
- Infinite raymarched mycelial structure merging organic curves with synthetic geometric nodes.
- Audio-reactive glowing spores that travel along the cyber-hyphae, bursting in brightness to bass and high frequencies.
- Ethereal subspace fog and volumetric bloom around the pulsating network cores.
- Interactive mouse gravity that bends the mycelium growth and draws spores toward the cursor.
- Dynamic chromatic aberration and subsurface scattering simulating synthetic-organic matter.

## Technical Implementation
- File: public/shaders/gen-cyber-organic-void-mycelium-pulsar.wgsl
- Category: generative
- Tags: ["organic", "cybernetic", "raymarching", "bioluminescent", "audio-reactive"]
- Algorithm: Raymarching infinite repetition domains combined with multi-frequency gyroid noise to construct tubular and branching organic structures mapped with neon color palettes.

### Core Algorithm
Raymarch through an unbounded 3D grid. Each grid cell contains a pseudo-random branch point formed by smooth-min blending of cylinders and spheres. Use complex spatial transformations (twisting and folding) driven by `u.config.x` (time) to simulate living, breathing expansion. Modulate the SDF scale and threshold with `extraBuffer[0]` (bass) for aggressive rhythmic throbbing.

### Mouse Interaction
The cursor position mapped to `u.zoom_config.y` and `u.zoom_config.z` acts as a localized gravitational anomaly. If `u.zoom_config.w > 0.0`, warp the global coordinates of the ray towards the 3D mouse position (inversely proportional to distance squared).

### Color Mapping / Shading
Base material is a dark, metallic obsidian utilizing fake ambient occlusion and specular highlights. Bioluminescence is layered by mapping distance-to-spore into emissive gradients (cyan, magenta, and toxic green), heavily augmented by a post-process bloom effect based on depth and emission intensity.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Cyber-Organic Void-Mycelium Pulsar
// Category: generative
// ----------------------------------------------------------------

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, yz=MouseUV, w=MouseDown
    zoom_params: vec4<f32>,  // x=Density, y=Spore Glow, z=Twist, w=Fog
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

const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ... Additional helper functions (SDFs, noise, coloring) ...

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // 1. Ray setup and mouse interaction logic
    // 2. Audio reaction mapping
    // 3. Raymarching loop (with ambient occlusion integration)
    // 4. Color / Shading calculations
    // 5. Output writing
}
```

## Parameters (for UI sliders)
- **Density (zoom_params.x)**: Default 1.0, Min 0.1, Max 3.0, Step 0.05
- **Spore Glow (zoom_params.y)**: Default 1.5, Min 0.0, Max 5.0, Step 0.1
- **Twist (zoom_params.z)**: Default 0.5, Min 0.0, Max 2.0, Step 0.01
- **Fog (zoom_params.w)**: Default 0.8, Min 0.0, Max 2.0, Step 0.05
