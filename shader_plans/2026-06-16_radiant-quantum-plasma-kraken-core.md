# New Shader Plan: Radiant Quantum-Plasma Kraken-Core

## Overview
A majestic, hyper-organic deep-space kraken composed of swirling quantum-plasma tentacles and a blinding radiant core that pulsates violently in sync with cosmic bass drops.

## Features
- Volumetric deep-space dark matter fog acting as the canvas.
- A central radiant core forged from intensely glowing quantum plasma.
- Multi-layered, hyper-organic tentacles generated using fractal tube SDFs.
- Audio-reactive bioluminescent waves rippling along the tentacles.
- Temporal twisting and swirling that mathematically distorts based on mouse interaction.
- Quantum glass refraction on the surface of the kraken's core.
- Procedural stardust particles dancing in the gravitational pull.

## Technical Implementation
- File: public/shaders/gen-radiant-quantum-plasma-kraken-core.wgsl
- Category: generative
- Tags: ["organic", "quantum", "cosmic", "plasma", "tentacles"]
- Algorithm: Raymarching with heavily domain-warped tubular SDFs and volumetric light scattering.

### Core Algorithm
- Uses an enhanced 3D noise function to displace a central sphere SDF (the core).
- Radiating outwards are 8 mathematical tentacles using `sdCapsule` or path-swept SDFs that are aggressively twisted using rotation matrices and domain repetition (`opRep`).
- The tentacles exhibit fractal details by layering multiple noise frequencies on the distance field.

### Mouse Interaction
- Mouse X/Y maps directly to the gravitational distortion field. When clicked, it generates a singularity that violently tugs the tentacles towards the cursor and increases the spin velocity of the core.

### Color Mapping / Shading
- A base color of abyssal blue that transitions into vibrant, liquid neon magenta and radiant gold at the core.
- Employs intense bloom/glow by accumulating density during the raymarching steps, resulting in a subsurface scattering effect.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Radiant Quantum-Plasma Kraken-Core
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Tentacle Twist, y=Plasma Glow, z=Core Heat, w=Void Depth
    ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```

## Parameters (for UI sliders)
- Tentacle Twist (1.0, 0.0, 5.0, 0.1)
- Plasma Glow (2.0, 0.0, 5.0, 0.1)
- Core Heat (1.5, 0.1, 3.0, 0.1)
- Void Depth (0.8, 0.0, 1.0, 0.05)

## Integration Steps
1. Create shader file `public/shaders/gen-radiant-quantum-plasma-kraken-core.wgsl`
2. Create JSON definition `shader_definitions/generative/gen-radiant-quantum-plasma-kraken-core.json`
3. Run `generate_shader_lists.js`
4. Upload via storage_manager
