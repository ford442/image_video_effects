# New Shader Plan: Stellar Fractal-Glass Loom

## Overview
A majestic, slow-shifting architecture of luminous, hyper-dimensional glass threads that weave intricate cosmic mandalas and impossibly complex fractal lattices, shimmering with nebulous stellar light.

## Features
- Intricate, recursive crystalline structures mimicking a multi-dimensional loom.
- Volumetric "glass" threads that refract and disperse light dynamically.
- Slow, deliberate metamorphic shifts driven by complex, overlapping low-frequency noise.
- Stellar core emissions at the heart of the loom that illuminate the structure from within.
- Fluid, organic integration of sharp geometric lattices and soft cosmic dust.
- Audio-reactive pulsing that brightens the threads along sharp structural intersections.
- Subsurface scattering effects through dense, nested geometry.

## Technical Implementation
- File: public/shaders/gen-stellar-fractal-glass-loom.wgsl
- Category: generative
- Tags: ["glass", "fractal", "loom", "stellar", "raymarching", "organic-geometry", "luminescent"]
- Algorithm: Raymarching complex folded SDFs (kaleidoscopic IFS) interwoven with multi-octave FBM for organic variation, simulating volumetric scattering and internal reflections.

### Core Algorithm
- Uses an Iterated Function System (IFS) with folding operations (`abs` and rotation) to create the fractal lattice.
- Modulates the scale and rotation parameters of the IFS folds using smooth, low-frequency 3D simplex noise (`u.config.x` for time).
- Combines sharp SDFs (boxes, cylinders for the "threads") with smooth min functions (`smin`) to weave them together.
- Volumetric lighting is calculated via raymarching accumulation, sampling density along the ray and accumulating color based on distance to the stellar core and intersection points.

### Mouse Interaction
- When clicked, `u.zoom_config.w > 0.0`, the mouse (`u.zoom_config.yz`) acts as a localized gravity well, pulling the glass threads towards the pointer.
- Uses a smooth polynomial falloff based on the distance between the ray position and the mouse-projected position in 3D space.
- Mouse movement also slightly torques the entire loom structure around the central axis.

### Color Mapping / Shading
- Deep cosmic blues and purples in the negative space.
- The glass threads are shaded with a mix of iridescent dispersion (dependent on view angle and normal) and warm stellar golds/oranges near the center.
- Fake ambient occlusion (based on raymarching step count) deepens the shadows in the dense fractal folds.
- "Bloom" is simulated by accumulating bright core colors as the ray passes near the center without hitting solid geometry.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Stellar Fractal-Glass Loom
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
  zoom_params: vec4<f32>,  // .x = Weave Complexity, .y = Loom Speed, .z = Thread Thickness, .w = Core Luminance
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ... helper functions (noise, smin) ...

// SDF for the Fractal Loom
fn map(p: vec3<f32>) -> f32 {
    // ... IFS folding logic ...
    return d;
}

// Raymarching Loop
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // ... camera setup, raymarching, shading, output ...
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Weave Complexity (1.5, 0.5, 3.0, 0.1) -> zoom_params.x
- Loom Speed (1.0, 0.1, 5.0, 0.1) -> zoom_params.y
- Thread Thickness (0.05, 0.01, 0.2, 0.01) -> zoom_params.z
- Core Luminance (1.2, 0.5, 3.0, 0.1) -> zoom_params.w

Integration Steps

1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
