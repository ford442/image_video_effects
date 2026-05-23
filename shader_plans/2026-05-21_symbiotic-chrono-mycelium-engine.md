# New Shader Plan: Symbiotic Chrono-Mycelium Engine

## Overview
A hyper-organic, ever-evolving cybernetic mycelial network that metabolizes temporal energy, pulsing with luminescent plasma as it entwines around a central quantum gear.

## Features
- **Hyper-Organic Cyber-Mycelium**: Branching SDF fractal networks that autonomously grow and recede, mimicking fungal intelligence.
- **Quantum Gear Core**: A perfectly geometric, rotating metallic core that emits high-frequency chronal energy outward.
- **Audio-Reactive Bioluminescence**: Mycelial nodes bloom with intensely glowing cyan and magenta plasma pulses synced to audio rhythms.
- **Temporal Phase Distortion**: Time dilation effects applied locally around the central engine, warping the coordinate space.
- **Fluid Nanite Swarms**: Audio-driven noise fields causing the mycelial tips to dissolve into swirling, glowing nanites.

## Technical Implementation
- File: public/shaders/gen-symbiotic-chrono-mycelium-engine.wgsl
- Category: generative
- Tags: ["organic", "mechanical", "mycelium", "audio-reactive", "quantum", "plasma"]
- Algorithm: Raymarching combining a KIFS (Kaleidoscopic Iterated Function System) for the mechanical core with recursive domain distortion and FBM noise for the organic mycelial network.

### Core Algorithm
Raymarching an SDF scene that blends hard-surface geometry (the quantum gear) with soft, organic displacement (the mycelium). The gear uses repeated polar domains and box SDFs, while the mycelium uses a smooth-minimum blended cylinder network displaced by Fractional Brownian Motion (FBM) noise. The low-frequency audio bands (`u.ripples`) drive the expansion of the mycelial network.

### Mouse Interaction
The mouse introduces a localized "temporal gravity well", bending the ray paths to simulate a magnetic/gravitational pull toward the cursor, effectively warping the view of the engine.

### Color Mapping / Shading
A physically inspired approach with deep metallic reflections for the core gear, contrasted with highly emissive, subsurface-scattering-like lighting for the mycelium. Colors range from deep obsidian to glowing bioluminescent cyan and magenta.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Symbiotic Chrono-Mycelium Engine
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

fn rotate(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ... (full skeleton with comments)
```

Parameters (for UI sliders)

- Mycelial Density (default: 3.0, min: 1.0, max: 10.0, step: 0.1)
- Plasma Glow (default: 2.0, min: 0.0, max: 5.0, step: 0.05)
- Temporal Warp (default: 0.5, min: 0.0, max: 2.0, step: 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
