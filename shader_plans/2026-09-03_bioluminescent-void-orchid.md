# New Shader Plan: Bioluminescent Void-Orchid

## Overview
A mesmerizing, abyssal flower composed of glowing, fractal-like tendrils that gently sway and pulse, mimicking bioluminescence in the deepest trenches of an alien ocean.

## Features
- Deep, high-contrast bioluminescent lighting (neon cyan, magenta, and deep violet)
- Fluid, organic motion driven by overlapping multi-frequency noise
- Fractal folding to create delicate, repeating petal structures
- Audio-reactive pulsing that brightens the core and accelerates tendril movement
- Interactive "water displacement" where the mouse drags and ripples the surrounding medium
- Soft bloom and sub-surface scattering approximations for an ethereal glow

## Technical Implementation
- File: public/shaders/gen-bioluminescent-void-orchid.wgsl
- Category: generative
- Tags: ["3d", "sdf", "raymarching", "bioluminescence", "organic", "audio-reactive", "interactive", "fractal"]
- Algorithm: Raymarching against a fractal SDF shaped like a blooming orchid, distorted by 3D simplex noise. Shading emphasizes emission over diffuse lighting, mapping distance-to-core and audio amplitude to intense, vibrant colors against an inky black background.

### Core Algorithm
The base SDF is a series of bent, tapering capsules arranged radially. We use polar repetition to distribute them around a central axis, and then apply folding (using `abs` and rotations) to create branching sub-tendrils. Time-based 3D noise (FBM) is added to the spatial coordinates before sampling the SDF, creating the underwater swaying effect. Audio data (from `dataTextureC`) modulates both the amplitude and speed of this noise.

### Mouse Interaction
The mouse simulates physical interaction with a viscous fluid. We track the mouse's projected position and velocity (derived from history or current delta). The space near the mouse is radially distorted, pulling the orchid's tendrils towards or away from the cursor as if caught in a wake, with a dampening effect that slowly restores their original position.

### Color Mapping / Shading
The color palette relies on high-emission bioluminescence. We calculate the distance to the "core" of the orchid and map it through a neon color ramp (e.g., deep blue at the tips to blinding magenta at the center). A fake subsurface scattering effect is achieved by accumulating color based on the number of raymarching steps taken (transmittance approximation). Audio peaks trigger intense white/cyan flashes at the core that propagate outward along the tendrils.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Bioluminescent Void-Orchid
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
  zoom_params: vec4<f32>,  // .x = Luminescence, .y = Audio Reactivity, .z = Sway Speed, .w = Tendril Complexity
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 120;
const SURF_DIST: f32 = 0.002;
const MAX_DIST: f32 = 80.0;

// 1. Noise Functions
fn hash13(p3: vec3<f32>) -> f32 { ... }
fn snoise3(x: vec3<f32>) -> f32 { ... }

// 2. Spatial Transformations (Rotations & Folding)
fn rot(a: f32) -> mat2x2<f32> { ... }
fn pModPolar(p: ptr<function, vec2<f32>>, repetitions: f32) { ... }

// 3. Map Function (SDF)
fn map(p: vec3<f32>, time: f32, audio: f32, mouseDistort: vec3<f32>) -> vec2<f32> { ... } // returns vec2(dist, materialID)

// 4. Lighting & Glow Accumulation
fn render(ro: vec3<f32>, rd: vec3<f32>, time: f32, audio: f32, mousePos: vec3<f32>) -> vec3<f32> { ... }

// 5. Main Compute Entry Point
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) { ... }
```

## Parameters (for UI sliders)
- Luminescence (1.0, 0.1, 3.0, 0.1)
- Audio Reactivity (1.0, 0.0, 5.0, 0.1)
- Sway Speed (1.0, 0.1, 4.0, 0.1)
- Tendril Complexity (3.0, 1.0, 6.0, 1.0)
