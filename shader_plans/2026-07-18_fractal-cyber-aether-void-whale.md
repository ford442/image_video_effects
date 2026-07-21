# New Shader Plan: Fractal Cyber-Aether Void-Whale

## Overview
A hyper-colossal cyber-organic void-whale composed of interwoven fractal geometry and liquid-aether plasma, gliding ominously through a dense, volumetric dark-matter ocean, its bioluminescent cyber-plating reacting deeply to acoustic bass resonance.

## Features
- Volumetric Dark-Matter Ocean rendering with heavy scattering and particle depth.
- Procedural Cyber-Whale structure created via layered SDF intersections and recursive fractal carving.
- Liquid Aether-Plasma veins pulsating underneath rigid geometric armor plates.
- Heavy acoustic reactivity: Sub-bass triggers massive luminescent ripples across the whale's hull.
- Quantum-Gravity Wake: Space warps slightly around the massive creature as it moves.
- Orbiting bio-mechanical krill swarms driven by boids-like noise.

## Technical Implementation
- File: public/shaders/gen-fractal-cyber-aether-void-whale.wgsl
- Category: generative
- Tags: ["organic", "cybernetic", "fractal", "volumetric", "cosmic", "audio-reactive"]
- Algorithm: Raymarching through a complex composite SDF (smooth-min for organic tissue, hard unions for cyber-plating) combined with fractal displacement (Mandelbulb/KIFS) and volumetric raycasting for the dark-matter ocean.

### Core Algorithm
- Primary geometry: Elongated, gracefully curved capsule SDF blended with tapered box SDFs for fins/flukes.
- Cyber-Plating: Iterative KIFS (Kaleidoscopic Iterated Function System) displacement subtracted from the base shape to carve intricate, mechanical-looking panel lines and armor segments.
- Bioluminescent Veins: Extracted from the inner region of the subtracted SDF areas, mapped to high-intensity plasma colors.
- Ocean Volume: Raymarching step includes a low-frequency 3D Worley noise density check to accumulate ambient darkness and scattered light, simulating a thick, murky deep-space medium.

### Mouse Interaction
- `u.zoom_config.y` and `u.zoom_config.z` offset the ray origin, effectively acting as a panning camera tracking the beast.
- The whale slowly undulates, but dragging the mouse forces the creature to slightly bank its massive body towards the cursor, creating a subtle parallax and scale reveal.

### Color Mapping / Shading
- Void Ocean: Deep indigo, crushed blacks, and subtle bioluminescent teal particulate.
- Whale Armor: Matte obsidian and gunmetal with metallic specular highlights.
- Aether-Veins: Blazing neon magenta and cyan gradients.
- Audio Reactivity (`plasmaBuffer[0].x`): Modulates the bloom intensity and the flow speed of the aether-veins, sending shockwaves of bright teal down the creature's length on heavy bass drops.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Fractal Cyber-Aether Void-Whale
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
    audioFreq: array<vec4<f32>, 16>,
    plasmaBuffer: array<vec4<f32>, 16>,
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>
}

// Transform functions (rotation, etc)
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a); let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Noise for volume and displacement
fn noise3D(p: vec3<f32>) -> f32 {
    // Standard procedural noise implementation
    return fract(sin(dot(p, vec3<f32>(12.9898, 78.233, 45.164))) * 43758.5453);
}

// Cyber-Fractal displacement (KIFS)
fn fractalDisplacement(p: vec3<f32>, iterations: i32) -> f32 {
    var q = p;
    var d = 0.0;
    var scale = 1.0;
    for (var i = 0; i < 4; i++) {
        if (i >= iterations) { break; }
        q = abs(q) - vec3<f32>(0.5, 0.2, 0.8) * scale;
        // Rotation and scaling logic
        scale *= 0.5;
        d += length(q) * scale;
    }
    return d;
}

// Main SDF map
fn map(p: vec3<f32>) -> vec2<f32> {
    // Base whale shape
    // Displacement for armor plating
    // Smooth blending
    // Return vec2(distance, material_id)
    return vec2<f32>(length(p) - 1.0, 0.0); // Placeholder
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

// Raymarching and Volumetric Accumulation loop
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec4<f32> {
    var d = 0.0;
    var col = vec3<f32>(0.0);
    var volumeDensity = 0.0;

    // Main loop
    for(var i = 0; i < 100; i++) {
        let p = ro + rd * d;
        let res = map(p);

        // Volumetric integration for dark-matter ocean
        volumeDensity += 0.01 * noise3D(p * 2.0);

        if(res.x < 0.001 || d > 50.0) { break; }
        d += res.x * 0.5; // Conservative step for fractals
    }

    // Surface shading and lighting
    return vec4<f32>(col, d);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let uv = vec2<f32>(global_id.xy) / u.resolution;
    // ... camera setup, mouse uniform usage, raymarching call
    // textureStore(writeTexture, global_id.xy, finalColor);
}
```

Parameters (for UI sliders)
Void Density (0.5, 0.0, 1.0, 0.05)
Fractal Depth (4.0, 1.0, 8.0, 1.0)
Armor Plating (0.7, 0.0, 1.0, 0.05)
Aether Flow (1.0, 0.1, 5.0, 0.1)
