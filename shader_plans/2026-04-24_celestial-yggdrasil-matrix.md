# New Shader Plan: Celestial Yggdrasil-Matrix

## Overview
An infinitely branching, cosmic tree constructed from intertwining ribbons of stellar plasma and quantum circuitry that pulses with the heartbeat of the universe, fusing organic arboreal forms with intricate cosmic geometry.

## Features
- Infinite KIFS-driven fractal branching structures mimicking a cosmic tree.
- Volumetric plasma sap flowing through translucent crystalline bark.
- Orbiting sub-atomic particle leaves that scatter and swarm with mouse movement.
- Audio-reactive energy pulses traveling up the root system.
- Deep cosmic void background with swirling nebula gas.
- Intricate chromatic dispersion and glowing bloom on branch intersections.

## Technical Implementation
- File: public/shaders/gen-celestial-yggdrasil-matrix.wgsl
- Category: generative
- Tags: ["organic", "cosmic", "fractal", "kifs", "plasma"]
- Algorithm: 3D Raymarching with Kaleidoscopic Iterated Function Systems (KIFS) for recursive branching, volumetric accumulation, and domain warping.

### Core Algorithm
Utilizes a recursive KIFS (Kaleidoscopic Iterated Function System) loop combined with rotation matrices and scaling to generate an infinite, self-similar tree structure. The SDF uses smooth-minimum (smin) to blend branches and a twisted cylinder base for the trunk. Domain warping creates the illusion of flowing plasma along the surface.

### Mouse Interaction
The mouse acts as a gravitational anomaly that bends the branches toward the cursor and causes the orbiting particle leaves to swarm rapidly around the interaction point.

### Color Mapping / Shading
Branches are rendered with a combination of subsurface scattering and chromatic dispersion to look like translucent crystal. Volumetric bloom creates the glowing plasma sap inside, transitioning from deep nebula purples to blinding stellar golds based on audio frequency and depth.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Celestial Yggdrasil-Matrix
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Branch Complexity, y=Plasma Flow, z=Gravity Warp, w=Glow Intensity
    ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let coords = vec2<i32>(id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    if (coords.x >= i32(res.x) || coords.y >= i32(res.y)) { return; }

    // Logic: Raymarching loop, KIFS fractal evaluation using zoom_params.x for loop count,
    // zoom_params.y for domain warp speed, and zoom_params.z for mouse gravity distortion.

    // Output color to writeTexture
}
```

## Parameters (for UI sliders)

- Branch Complexity (default: 5.0, min: 1.0, max: 10.0, step: 1.0)
- Plasma Flow (default: 1.0, min: 0.1, max: 5.0, step: 0.1)
- Gravity Warp (default: 0.5, min: 0.0, max: 2.0, step: 0.05)
- Glow Intensity (default: 1.2, min: 0.0, max: 3.0, step: 0.1)

## Integration Steps

- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
