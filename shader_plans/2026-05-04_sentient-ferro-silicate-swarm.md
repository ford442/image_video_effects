# New Shader Plan: Sentient Ferro-Silicate Swarm

## Overview
A hyper-dynamic, liquid-metal particle swarm that self-assembles into brutalist geometric architectures before dissolving back into a chaotic, churning ferro-fluid storm, reacting violently to audio impulses.

## Features
- Millions of sentient ferro-particles exhibiting flocking, seeking, and assembling behaviors.
- Real-time transition between chaotic fluid dynamics and rigid, fractal, brutalist structures.
- Audio-reactive magnetic repulsion that shatters the geometric forms upon heavy bass impacts.
- Hyper-reflective, liquid-chrome surface rendering with dynamic iridescent oil-spill dispersion.
- Volumetric, bioluminescent heat signatures radiating from the inner core of the swarm.

## Technical Implementation
- File: public/shaders/gen-sentient-ferro-silicate-swarm.wgsl
- Category: generative
- Tags: ["mechanical", "particle-system", "audio-reactive", "fluid-dynamics", "fractal"]
- Algorithm: A dual-pass compute shader utilizing a curl-noise driven particle system mapped onto a dynamic Signed Distance Field (SDF). The SDF defines the target brutalist geometry, which the particles interpolate towards based on audio thresholds.

### Core Algorithm
- **Particle System**: Ping-pong buffer implementation updating position and velocity.
- **Flocking & Seeking**: Boids-like behavior combined with an SDF-seeking force.
- **SDF Target**: A KIFS (Kaleidoscopic Iterated Function System) fractal that morphs its parameters over time, defining the target resting state for the swarm.
- **Audio Modulation**: Bass frequencies (extracted from audio/video luminance or simulated) inject massive outward velocity, overcoming the SDF attraction to shatter the structure.

### Mouse Interaction
- The mouse acts as a localized, extreme-gravity magnetic anomaly. Left-clicking reverses the polarity, forcefully repelling the swarm and creating localized shockwaves of geometric shattering.

### Color Mapping / Shading
- Particles are shaded using their local velocity magnitude and density.
- High density areas render as hyper-reflective liquid chrome.
- High velocity areas (recently shattered) bleed volumetric heat mapping via `plasmaBuffer`, resulting in neon-orange/cyan irradiance.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Sentient Ferro-Silicate Swarm
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// ... additional bindings for particle buffers

struct Particle {
    pos: vec2<f32>,
    vel: vec2<f32>,
    life: f32,
    mass: f32,
}

// ... Uniforms, params ...

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) coords: vec3<u32>) {
    // 1. Boundary Check
    if (coords.x >= u32(u.config.x) || coords.y >= u32(u.config.y)) { return; }

    // 2. Fetch particle data
    // 3. Compute curl noise & SDF attraction forces
    // 4. Apply audio-reactive shattering
    // 5. Update particle position and write out
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Swarm Cohesion (0.5, 0.0, 1.0, 0.01)
- Fractal Rigidity (0.7, 0.0, 1.0, 0.01)
- Shatter Force (0.8, 0.0, 2.0, 0.05)
- Oil-Spill Iridescence (0.4, 0.0, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
