# New Shader Plan: Silica Tsunami

## Overview
A colossal, slow-motion wave of millions of refractive glass-like particles that crests and shatters into dust, dynamically reshaping itself around the viewer's mouse and surging to the beat of incoming audio.

## Features
- **Millions of Refractive Particles**: Uses a compute shader to manage massive particle counts simulating fluid dynamics and surface tension.
- **Glass/Silica Materiality**: Advanced shading incorporating fake refraction, chromatic aberration, and specular highlights to simulate shattered glass.
- **Audio-Reactive Cresting**: Audio amplitude directly drives the wave's height, cresting force, and the explosive energy of the particle spray.
- **Mouse-Repellent Gravity Well**: The cursor acts as a localized repulsor, parting the wave and scattering the glass particles as they crash.
- **Slow-Motion Time Distortion**: Time scaling allows the chaotic wave crash to be frozen or slowed down for intricate visual inspection.

## Technical Implementation
- File: public/shaders/gen-silica-tsunami.wgsl
- Category: generative
- Tags: ["particles", "fluid", "glass", "audio-reactive", "physics", "abstract"]
- Algorithm: Compute-based particle simulation with curl noise and fluid-like constraint solving, rendered via instancing or splatting with refractive screen-space approximations.

### Core Algorithm
The compute shader manages a buffer of particle structs (position, velocity, lifetime, mass). It applies a base directional force to simulate the wave's advance, combined with 3D curl noise for turbulent interior flow. A pseudo-fluid constraint system (or SPH approximation if performance allows) maintains density. The wave shape is defined by a moving SDF plane that particles are attracted to, which crests and breaks based on a sine/noise displacement driven by time and audio.

### Mouse Interaction
The mouse cursor is projected into the 3D space as a spherical repulsion zone. The inverse square law is applied to calculate the repulsive force on nearby particles, forcing them to scatter outward. The `u_mouse.z` (click) state significantly increases the repulsion radius and force, effectively creating a "splash" crater in the wave.

### Color Mapping / Shading
Particles are shaded using their velocity to determine color, shifting from deep ocean blues at low speeds to bright cyan and white at high speeds (the foam/spray). A post-processing approach or specialized blending simulates refraction by distorting the background based on particle density, adding a slight RGB channel offset for chromatic aberration. The material includes a high specular exponent for sharp, glass-like glints.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Silica Tsunami
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    mouse: vec4<f32>,
    audio: vec4<f32>,
    // custom params mapped from zoom_params
    wave_height: f32,       // zoom_params.x
    particle_chaos: f32,    // zoom_params.y
    time_scale: f32,        // zoom_params.z
    refraction_index: f32,  // zoom_params.w
}

// Particle Struct
struct Particle {
    pos: vec3<f32>,
    vel: vec3<f32>,
    life: f32,
}

// Compute pass for physics update
@compute @workgroup_size(64)
fn update_particles(@builtin(global_invocation_id) id: vec3<u32>) {
    // 1. Read particle state
    // 2. Apply curl noise turbulence based on particle_chaos
    // 3. Apply wave cresting logic driven by audio.x and wave_height
    // 4. Calculate mouse repulsion
    // 5. Update velocity and position (scaled by time_scale)
    // 6. Write back state
}

// Render pass (if instanced, or splatting into writeTexture)
fn render_particles() {
    // Shade based on velocity
    // Apply pseudo-refraction and chromatic aberration
}
```

## Parameters (for UI sliders)

| Name | Default | Min | Max | Step |
|------|---------|-----|-----|------|
| Wave Height (zoom_params.x) | 1.0 | 0.1 | 3.0 | 0.1 |
| Particle Chaos (zoom_params.y) | 0.5 | 0.0 | 2.0 | 0.05 |
| Time Scale (zoom_params.z) | 1.0 | 0.01| 2.0 | 0.01 |
| Refraction (zoom_params.w) | 0.8 | 0.0 | 1.5 | 0.1 |

## Integration Steps

1. Create shader file `public/shaders/gen-silica-tsunami.wgsl` with the proposed WGSL skeleton.
2. Create JSON definition `shader_definitions/generative/gen-silica-tsunami.json` mapping the UI parameters.
3. Run `node scripts/generate_shader_lists.js` to update the shader manifest.
4. Upload assets via storage_manager (if necessary, though this is primarily procedural).
5. After creating the file, add it to the queue by running:
   `python scripts/manage_queue.py add "2026-03-08_silica-tsunami.md" "Silica Tsunami"`
