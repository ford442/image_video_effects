# New Shader Plan: Kinetic Bioluminescent Obsidian-Coral Reactor

## Overview
A mesmerizing descent through a brutalist lattice of jet-black obsidian that is continuously overgrown and consumed by a pulsing, bioluminescent cyan and magenta "coral" energy-fluid. It feels like exploring the heart of an ancient, abyssal alien supercomputer that uses organic life as its power source.

## Features
- Infinite raymarched tunnel structure utilizing complex domain repetition and Menger sponge variations.
- High-contrast material blending: sharp, highly reflective jet-black obsidian vs. soft, volumetric, glowing organic fluid.
- Bioluminescent fluid dynamics simulated via layered multi-octave simplex noise displacing the surface.
- Audio-reactive energy pulses: bass hits surge bright cyan energy through the coral veins, while treble causes the obsidian to locally fracture and shimmer.
- Mouse-driven "lantern" effect: the cursor casts a local volumetric light that reveals microscopic prismatic imperfections in the obsidian.
- Chromatic aberration and heavy depth-of-field blur on the tunnel periphery to enhance scale and depth.

## Technical Implementation
- File: public/shaders/gen-kinetic-bioluminescent-obsidian-coral-reactor.wgsl
- Category: generative
- Tags: ["organic", "brutalist", "bioluminescent", "tunnel", "audio-reactive", "raymarching", "fractal"]
- Algorithm: 3D Raymarching through a boolean intersection of a domain-repeated Menger sponge (obsidian) and a smooth, low-frequency volumetric noise field (coral).

### Core Algorithm
The scene is built using a raymarching loop evaluating a composite Signed Distance Field (SDF). The base architecture is a hollowed-out grid created via `mod` domain repetition and intersecting box SDFs, recursively folded to create brutalist Menger-like cavities. A secondary smooth SDF, driven by 3D simplex noise and fractional Brownian motion (fBm), represents the organic coral. These two SDFs are combined using a `smin` (smooth minimum) function, creating a seamless, creeping transition between the rigid geometry and the organic growth.

### Mouse Interaction
The mouse acts as a localized light source and gravity well. As rays are marched, the distance to the mouse projection in 3D space is calculated. Within this radius, the obsidian SDF's surface normal is slightly perturbed to reveal a micro-facet structure, and a secondary bright point-light illumination model is added, allowing the user to "shine a flashlight" into the dark recesses of the lattice.

### Color Mapping / Shading
The shader uses a dual-material shading system. The obsidian is shaded using a Blinn-Phong model with zero base color, extremely high gloss, and a harsh, tight specular highlight, reflecting an abstract HDRI environment approximation. The coral is shaded purely via emission, using a cosine palette (`cos(a + b*t + c*t^2)`) that cycles between deep oceanic cyan and hot magenta. The emission intensity is modulated by the distance from the coral SDF surface, creating a subsurface glow.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Kinetic Bioluminescent Obsidian-Coral Reactor
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
    frame: u32,
    // Note: Standard fields below, mapping to UI params
    zoom_params: vec4<f32>,   // mapped to color_params in plan
    speed_params: vec4<f32>,  // mapped to morph_params in plan
    extra_params: vec4<f32>,  // mapped to glow_params in plan
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coords = vec2<i32>(global_id.xy);
    if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) { return; }

    let base_uv = vec2<f32>(coords) / vec2<f32>(dims);
    var uv = base_uv * 2.0 - 1.0;
    let aspect = f32(dims.x) / f32(dims.y);
    uv.x *= aspect;

    // Raymarching setup
    var ro = vec3<f32>(0.0, 0.0, -2.0 + u.time * u.speed_params.x); // Camera moves forward
    var rd = normalize(vec3<f32>(uv, 1.5));

    // ... (raymarch loop, SDFs, shading) ...

    var final_color = vec3<f32>(0.0); // Output color

    textureStore(writeTexture, coords, vec4<f32>(final_color, 1.0));
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Color Shift `zoom_params.x` (0.5, 0.0, 1.0, 0.01)
- Coral Density `zoom_params.y` (1.2, 0.5, 3.0, 0.1)
- Fluid Speed `speed_params.x` (1.0, 0.0, 3.0, 0.05)
- Lattice Complexity `speed_params.y` (3.0, 1.0, 5.0, 1.0)
- Glow Intensity `extra_params.x` (2.0, 0.1, 5.0, 0.1)
- Void Darkness `extra_params.y` (0.8, 0.0, 1.0, 0.05)
