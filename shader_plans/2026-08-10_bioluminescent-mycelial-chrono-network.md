# New Shader Plan: Bioluminescent Mycelial Chrono-Network

## Overview
A sprawling, organic neural-network of luminescent fungal threads that pulsate and grow over time, responding dynamically to temporal shifts and spatial disturbances. The aesthetic combines deep abyssal bioluminescence with intricate, time-dilated organic growth patterns.

## Features
- **Dynamic Growth Algorithms**: Raymarched organic tendrils that branch and fuse based on a 4D noise field.
- **Temporal Pulsation**: Luminescence that travels along the network pathways, simulating nutrient or energy transfer.
- **Chrono-Distortion Fields**: Areas where time appears to slow down or speed up, warping the network's geometry.
- **Interactive Spore Clusters**: Mouse interaction spawns high-density glowing spore clouds that perturb the mycelial growth.
- **Subsurface Scattering Approximation**: Deep, glowing cores surrounded by translucent outer layers for a fleshy, organic feel.
- **Adaptive Depth of Field**: Cinematic blurring that focuses on the most active growth nodes.
- **Color Phase Shifting**: Gradient shifts from deep abyssal blues to toxic neon greens based on network density and age.

## Technical Implementation
- File: public/shaders/gen-bioluminescent-mycelial-chrono-network.wgsl
- Category: generative
- Tags: ["organic", "bioluminescence", "network", "raymarching", "temporal", "mycelium"]
- Algorithm: Raymarching with domain warping, 4D Simplex noise for organic branching, and SDF-based volumetric glow accumulation.

### Core Algorithm
The base geometry is driven by a smooth minimum (smin) combination of multiple wandering cylindrical SDFs (the mycelial threads). The paths of these cylinders are distorted by a 4D noise function (XYZ + Time) to create organic, unpredictable meandering. A secondary high-frequency noise adds texture (spores/bumps) to the surface. Growth is simulated by masking the SDF based on a distance-from-origin metric modulated by time.

### Mouse Interaction
The mouse acts as a localized gravity/energy well. When interacting, it creates a spherical distortion field that bends the mycelial threads towards it (or away from it, depending on a parameter). It also locally accelerates the color phase shift and increases the emission intensity, mimicking a reaction to touch.

### Color Mapping / Shading
The shading relies heavily on volumetric emission accumulation rather than standard surface lighting. As the raymarches through the SDF, it accumulates color based on the proximity to the thread cores. The color palette maps network density to a gradient: low density = dark teal/blue, high density = bright cyan/green. A simulated subsurface scattering is achieved by calculating the gradient of the SDF and applying a rim light effect with a highly saturated color.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Bioluminescent Mycelial Chrono-Network
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
  zoom_params: vec4<f32>,  // .x = Growth Rate, .y = Network Density, .z = Glow Intensity, .w = Spore Activity
  ripples: array<vec4<f32>, 50>,
};

// ... (Utility functions: rot, smin, noise3d, etc.) ...

// SDF for the mycelial network
fn map(p: vec3<f32>) -> f32 {
    // Basic structural noise
    var d = 100.0;
    // ... complex smin blending of noise-distorted cylinders ...
    return d;
}

// Raymarching and Glow Accumulation
fn render(ro: vec3<f32>, rd: vec3<f32>) -> vec4<f32> {
    var t = 0.0;
    var glow = vec3<f32>(0.0);
    // ... raymarch loop with volumetric accumulation ...
    return vec4<f32>(color, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // ... Setup UVs, camera, ray direction ...
    // ... Handle Mouse Interaction (u.zoom_config.yz) ...
    // ... Call render() and write to texture ...
}
```

## Parameters (for UI sliders)
- **Growth Rate**: `zoom_params.x` (default: 0.5, min: 0.1, max: 2.0, step: 0.05) - Controls the speed of the temporal evolution and pulsation.
- **Network Density**: `zoom_params.y` (default: 1.0, min: 0.2, max: 3.0, step: 0.1) - Determines how tightly packed and branching the threads are.
- **Glow Intensity**: `zoom_params.z` (default: 1.5, min: 0.0, max: 5.0, step: 0.1) - Scales the overall brightness and volumetric bloom of the network.
- **Spore Activity**: `zoom_params.w` (default: 0.3, min: 0.0, max: 1.0, step: 0.05) - Controls the frequency and brightness of the high-frequency surface noise/spores.
