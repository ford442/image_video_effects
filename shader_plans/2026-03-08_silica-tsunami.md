# Silica Tsunami - Generative Shader Plan

## Overview
A slow-motion wave of refractive glass-like particles that crests and shatters, dynamically reshaping around the mouse and reacting to audio amplitude.

## Features
- **Slow-motion Cresting Wave**: An infinite field of particles moving like a tsunami.
- **Refractive Glass Shading**: Simulated caustics and Fresnel lighting.
- **Audio Reactivity**: Audio amplitude (u.config.y) drives wave cresting power and particle displacement.
- **Mouse Interaction**: Mouse acts as an attractor/repulsor in the wave.

## Technical Implementation
- Implemented via raymarching with domain repetition (opRep) for infinite particles.
- Base SDF shapes (boxes/spheres) modified by sine waves and noise.
- Negate SDF for interior rendering if necessary for bubbles/refraction.
- `u.config.y` controls the vertical displacement and chaos.

### Proposed Code Structure
```wgsl
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
// ... standard bindings ...

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

fn hash31(p: vec3<f32>) -> f32 { ... }
fn rot(a: f32) -> mat2x2<f32> { ... }
fn map(p: vec3<f32>) -> vec3<f32> { ... }
fn calcNormal(p: vec3<f32>) -> vec3<f32> { ... }

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) { ... }
```

### Parameters
| Parameter           | Range    | Default | Description                                 |
|---------------------|----------|---------|---------------------------------------------|
| waveHeight          | 0-5      | 2.0     | Maximum height of the crest                 |
| glassRefraction     | 0-1      | 0.8     | Intensity of the glass fresnel/refraction   |
| particleDensity     | 0.1-2.0  | 1.0     | Spacing of the grid domain                  |
| audioReactivity     | 0-3      | 1.5     | Multiplier for audio-driven chaos           |

## Integration Steps
1. Create `public/shaders/gen-silica-tsunami.wgsl` matching the structure above.
2. Create `shader_definitions/generative/gen-silica-tsunami.json` with the specified parameters mapped to `u.zoom_params`.
3. Generate shader lists.
4. Upload to storage manager and mark as complete.