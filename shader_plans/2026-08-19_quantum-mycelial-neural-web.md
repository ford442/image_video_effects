# New Shader Plan: Quantum Mycelial Neural Web

## Overview
An emergent, bioluminescent network of mycelial structures that pulses and evolves like a cosmic brain, bridging organic growth patterns with quantum probabilistic entanglement.

## Features
- Volumetric network generation simulating fractal mycelial growth in a 3D domain space.
- Bioluminescent pulsing algorithms driven by a global simulation time for living, breathing structures.
- Multi-scale, 3D curl noise integration resulting in smooth, tangled organic webs.
- Audio-reactive nodes mapping frequency data (dataTextureC) to emission intensity and growth velocity.
- Depth-aware subsurface scattering approximation via recursive marching samples.
- Fluid mouse interaction acting as an "attractor point", feeding energy into local hyphae.

## Technical Implementation
- File: public/shaders/gen-quantum-mycelial-neural-web.wgsl
- Category: generative
- Tags: ["organic", "network", "volumetric", "mycelial", "bioluminescence", "raymarching"]
- Algorithm: Raymarching volumetric distances combined with layered 3D Curl Noise and fractional Brownian motion (fBm) to sculpt continuous, interwoven fibrous networks with bloom-based post-accumulation.

### Core Algorithm
A volumetric raymarcher utilizing a base domain structured by 3D Curl Noise to evaluate continuous vector fields. The vector field traces pathways representing "hyphae". A localized Signed Distance Field (SDF) of thick procedural fibers evaluates the network's density. Fractal Brownian motion (fBm) adds micro-surface detail.

### Mouse Interaction
The mouse acts as a localized gravity and energy well. When clicked, `u.zoom_config.yz` translates into a 3D spatial coordinate affecting the ray direction. Ray intersections passing near this point experience severe domain warping, bending the mycelial threads towards the mouse and intensely amplifying local emission colors.

### Color Mapping / Shading
The shading utilizes a deep, abyssal background fading into bioluminescent cyan, magenta, and electric blue hues along the fibers. Subsurface scattering is faked through ambient occlusion and soft shadows accumulated during raymarching. A global "pulse" maps time-varying emissions along the threads.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Quantum Mycelial Neural Web
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
  zoom_params: vec4<f32>,  // .x = Web Density, .y = Pulse Speed, .z = Bioluminescence, .w = Entanglement
  ripples: array<vec4<f32>, 50>,
};

// --- CORE UTILITIES ---
// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Noise for organic structures
fn hash33(p3: vec3<f32>) -> vec3<f32> {
    var p = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p = p + dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

// Distance estimation for mycelial network
fn map(p: vec3<f32>, time: f32) -> f32 {
    // ... SDF logic for intersecting fibers ...
    return 1.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Check bounds
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let time = u.config.x;

    // ... Raymarching, lighting, and rendering logic ...

    textureStore(writeTexture, global_id.xy, vec4<f32>(0.0, 0.5, 1.0, 1.0));
}
```

Parameters (for UI sliders)

Web Density (0.5, 0.1, 2.0, 0.01)
Pulse Speed (1.0, 0.1, 5.0, 0.1)
Bioluminescence (0.8, 0.0, 2.0, 0.05)
Entanglement (0.2, 0.0, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
