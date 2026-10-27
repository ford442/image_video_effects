# New Shader Plan: Magmatic Cyber-Hex Lattice

## Overview
A high-tech hexagonal grid structure floating over a glowing, slow-churning lake of cybernetic magma.

## Features
- Hexagonal domain repetition for the grid structure.
- Slowly morphing Voronoi-based noise for the magmatic flow.
- Neon edge-lighting on the hex grid.
- Smooth min/max for blending structural elements.
- Depth-based color mapping for the magma.
- Mouse interaction that creates a localized magnetic distortion in the grid.

## Technical Implementation
- File: public/shaders/gen-magmatic-cyber-hex-lattice.wgsl
- Category: generative
- Tags: ["hex", "magma", "cyber", "grid", "voronoi"]
- Algorithm: Raymarching an SDF scene comprising a hex grid and a fluid noise plane.

### Core Algorithm
The scene uses a raymarcher. The main SDF is a combination of a hexagonal grid (created via domain repetition) and a wavy base plane (displaced by Voronoi noise to simulate magma). The hex grid uses `sdHexPrism`.

### Mouse Interaction
When the mouse is clicked (`u.zoom_config.w > 0.5`), the hex grid vertices are displaced towards the mouse coordinate, creating a gravity well effect. The displacement strength falls off inversely with distance.

### Color Mapping / Shading
The magma uses a gradient from deep crimson to bright orange/yellow based on its height displacement. The hex grid is mostly dark metallic with glowing cyan neon edges along its top surface.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Magmatic Cyber-Hex Lattice
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
  config: vec4<f32>,              // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,         // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,         // .xyzw = user params p1..p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

// --- HELPER FUNCTIONS ---
fn sdHexPrism(p: vec3<f32>, h: vec2<f32>) -> f32 {
    let k = vec3<f32>(-0.8660254, 0.5, 0.57735);
    var p_abs = abs(p);
    p_abs.x -= 2.0 * min(dot(k.xy, p_abs.xy), 0.0) * k.x;
    p_abs.y -= 2.0 * min(dot(k.xy, p_abs.xy), 0.0) * k.y;
    let d = vec2<f32>(
        length(p_abs.xy - vec2<f32>(clamp(p_abs.x, -k.z*h.x, k.z*h.x), h.x))*sign(p_abs.y - h.x),
        p_abs.z - h.y
    );
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// --- MAIN COMPUTE SHADER ---
@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
      return;
  }
  let uv = vec2<f32>(global_id.xy) / resolution.xy;
  let color = vec4<f32>(uv, 0.5 + 0.5 * sin(u.config.x), 1.0);
  textureStore(writeTexture, vec2<i32>(global_id.xy), color);
}
```

Parameters (for UI sliders)

Hex Scale (1.0, 0.1, 5.0, 0.1)
Magma Speed (1.0, 0.0, 3.0, 0.1)
Neon Intensity (1.0, 0.0, 5.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
