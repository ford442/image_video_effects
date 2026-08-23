# New Shader Plan: Cybernetic Aether-Moth Chrysalis

## Overview
A hyper-intricate cyber-organic cocoon pulses with bioluminescent plasma trails and crystalline micro-circuitry, breathing and evolving over time. The aesthetic is a high-contrast blend of deep abyssal blues and bioluminescent neon teals/purples, marrying the geometric precision of synthetic engineering with the chaotic fluidity of organic metamorphosis.

## Features
- **Fractal Micro-Circuitry Lattice:** Complex 3D Voronoi / Hexagonal cellular structures forming the outer carapace.
- **Pulsating Bioluminescent Plasma Core:** A fluid, glowing inner core driven by layered FBM (Fractional Brownian Motion) and smooth min SDF blending.
- **Audio-Reactive Fiber Optics:** Glowing cilia-like threads branching outward that vibrate and flash based on dataTextureC inputs (frequency spectrum).
- **Temporal Metamorphosis:** A slow, continuous shifting of the core geometry and outer shell, simulating a breathing entity.
- **Holographic Chromatic Aberration:** Edge-lit highlights with spectral color dispersion via raymarching optical refraction simulation.
- **Dynamic Mouse Interaction:** The chrysalis responds to mouse movement by tilting, revealing inner depths through translucent gaps, and intensifying core brightness.

## Technical Implementation
- File: public/shaders/gen-cybernetic-aether-moth-chrysalis.wgsl
- Category: generative
- Tags: ["organic", "cybernetic", "fractal", "bioluminescence", "plasma", "audio-reactive"]
- Algorithm: Raymarching with domain distortion, 3D Voronoi cellular noise, layered FBM, and SDF smooth blending.

### Core Algorithm
- **Noise Type:** Combination of 3D Voronoi for the mechanical outer shell and 4-octave FBM for the inner plasma core.
- **Domain Repetition/Distortion:** Space is folded radially and twisted along the Y-axis (using `rot()` functions) to create the symmetrical, yet organic cocoon shape.
- **SDFs:** Base shape is an elongated capsule blended smoothly with a distorted sphere. The Voronoi pattern is subtracted from the outer shell to create intricate viewing windows into the core.
- **Audio Reactivity:** `textureSampleLevel(dataTextureC, non_filtering_sampler, vec2<f32>(uv.x, 0.5), 0.0).r` is sampled to modulate the glow intensity and the displacement of the fiber optic threads.

### Mouse Interaction
- `u.zoom_config.yz` mapped to tilt the entire object via a rotation matrix around the X and Y axes (simulating orbiting/inspecting the chrysalis).
- A localized gravity well/distortion field near the mouse position pushes the outer lattice apart slightly to reveal more of the intense core.

### Color Mapping / Shading
- **Outer Shell:** Dark, metallic obsidian with specular highlights (calculated using Blinn-Phong-like lighting and normals estimated from the SDF).
- **Inner Core:** Subsurface scattering simulation using a high-intensity radial gradient (neon purple to cyan).
- **Bloom:** Emissive components (core and fiber optics) accumulate high energy values to be bloomed in post-processing.
- **Shadows:** Soft raymarched shadows to give depth to the lattice over the glowing core.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Cybernetic Aether-Moth Chrysalis
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
  zoom_params: vec4<f32>,  // .x = Point Density, .y = Rotation Speed, .z = Point Size, .w = Color Shift
  ripples: array<vec4<f32>, 50>,
};

// ----------------------------------------------------------------
// Helper Functions (Rotations, Noise, SDFs)
// ----------------------------------------------------------------
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ... (Hash, 3D Noise, Voronoi)

// ----------------------------------------------------------------
// Map Function
// ----------------------------------------------------------------
fn map(p: vec3<f32>) -> vec2<f32> {
    // 1. Mouse Interaction & Space folding
    // 2. Audio sampling from dataTextureC
    // 3. Core SDF (Capsule + FBM)
    // 4. Shell SDF (Capsule - Voronoi)
    // 5. Smooth Min blending
    // Return vec2(distance, material_id)
    return vec2<f32>(0.0, 0.0);
}

// ----------------------------------------------------------------
// Lighting & Shading
// ----------------------------------------------------------------
fn getNormal(p: vec3<f32>) -> vec3<f32> {
    // Standard normal estimation
    return vec3<f32>(0.0);
}

fn render(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    // Raymarching loop
    // Accumulate glow (bloom)
    // Calculate materials based on material_id
    return vec3<f32>(0.0);
}

// ----------------------------------------------------------------
// Main Compute
// ----------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // Setup UVs, Ray Origin, Ray Direction
    // Call render()
    // Write to textureStore
}
```

## Parameters (for UI sliders)

- **Point Density** (mapped to Core Complexity): default 0.5, min 0.0, max 1.0, step 0.01
- **Rotation Speed** (mapped to Chrysalis Spin): default 0.2, min 0.0, max 1.0, step 0.01
- **Point Size** (mapped to Lattice Thickness): default 0.4, min 0.1, max 1.0, step 0.01
- **Color Shift** (mapped to Core Hue Shift): default 0.0, min 0.0, max 1.0, step 0.01

## Integration Steps

1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-08-16_cybernetic-aether-moth-chrysalis.md" "Cybernetic Aether-Moth Chrysalis"
Reply with only: "✅ Plan created and queued: 2026-08-16_cybernetic-aether-moth-chrysalis.md"