# New Shader Plan: Chronodynamic Aether-Weaver Automata

## Overview
A majestic, self-assembling celestial loom that continuously weaves threads of pure liquid-aether and fractured time into hyper-complex, bioluminescent tapestries that ripple to ambient sonic frequencies.

## Features
- **Quantum Thread Physics:** Generates hundreds of intersecting splines representing glowing aether strings that mathematically braid into one another.
- **Bioluminescent Nodes:** Where threads intersect, pulsing energy nodes emerge, mapped to audio reactivity.
- **Temporal Echo Trails:** Uses a feedback loop to leave glowing ghost-trails of the weaving process, simulating time dilation.
- **Mechanical Loom Architecture:** The background features massive, slowly rotating hyper-dimensional gears that guide the thread splines.
- **Chrono-Distortion Ripples:** Mouse interaction bends the fabric of space-time, pulling threads toward a singularity point.
- **Iridescent Plasma Shading:** Employs a complex subsurface scattering simulation with shifting interference patterns mapped through the `plasmaBuffer`.

## Technical Implementation
- File: public/shaders/gen-chronodynamic-aether-weaver-automata.wgsl
- Category: generative
- Tags: ["cosmic", "mechanical", "quantum", "bioluminescent", "automata", "audio-reactive"]
- Algorithm: Raymarching combined with multi-pass spline evaluation and reaction-diffusion-based feedback blending.

### Core Algorithm
- Uses an SDF-based raymarcher to render the immense background gears.
- Simulates the "threads" using an array of splines modulated by 3D simplex noise and audio data.
- The background generates subtle volumetric fog to give scale.
- A ping-pong feedback loop applies slight zoom and rotational distortion, mimicking temporal shifts.

### Mouse Interaction
- The mouse acts as a localized gravity well, altering the tangent vectors of the nearby splines and distorting the underlying SDF of the gears, producing a lensing effect.

### Color Mapping / Shading
- The threads are colored using the `plasmaBuffer`, sampling based on the string's index and local curvature.
- The gears feature a dark, metallic shader with intense edge-wear glow.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Chronodynamic Aether-Weaver Automata
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// --- UNIFORMS & CONSTANTS ---
// u.config.x = time
// u.config.y = mouse_x
// u.config.z = mouse_y
// u.config.w = mouse_down (1.0 or 0.0)

// Parameters
// Thread Count (100, 10, 500, 10)
// Loom Rotation Speed (1.0, -5.0, 5.0, 0.1)
// Aether Bloom (0.5, 0.0, 1.0, 0.01)
// Temporal Decay (0.95, 0.5, 0.99, 0.01)

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(readTexture));
    let uv = vec2<f32>(id.xy) / dims;
    let pos = (uv - 0.5) * 2.0;

    // ... (raymarching logic for loom gears)
    // ... (spline evaluation for aether threads)
    // ... (mouse interaction gravity well logic)
    // ... (color mapping using plasmaBuffer)
    // ... (temporal feedback integration)

    let final_color = vec4<f32>(uv, 0.5 + 0.5 * sin(u.config.x), 1.0); // Placeholder
    textureStore(writeTexture, vec2<i32>(id.xy), final_color);
}
```

## Parameters (for UI sliders)
- Thread Count (100, 10, 500, 10)
- Loom Rotation Speed (1.0, -5.0, 5.0, 0.1)
- Aether Bloom (0.5, 0.0, 1.0, 0.01)
- Temporal Decay (0.95, 0.5, 0.99, 0.01)
