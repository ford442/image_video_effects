# New Shader Plan: Quantum Aether-Origami

## Overview
A hyper-dimensional expanse of iridescent, self-folding light-sheets that crease, snap, and unfold like cosmic origami, collapsing into singularities to the beat of sound.

## Features
- Infinite 3D origami structures constructed via sharp-angled domain repetitions and intersecting plane SDFs.
- Crease lines that pulse with blinding quantum-photonic light when audio amplitudes surge.
- Thin-film interference rendering on the "paper", producing chromatic aberration and oily rainbows.
- Structures dynamically fold and unfold along mathematical hinges driven by time and beat sequences.
- A magnetic cursor interaction that "unfolds" or flattens the local geometry into a planar mirror.

## Technical Implementation
- File: public/shaders/gen-quantum-aether-origami.wgsl
- Category: generative
- Tags: ["origami", "quantum", "geometry", "interference", "audio-reactive"]
- Algorithm: Raymarching with intersecting multi-planar SDFs, sharp rotational domain folding (kaleidoscopic folding), and thin-film lighting.

### Core Algorithm
The geometry is built using recursive space-folding (like the "KIFS" - Kaleidoscopic Iterated Function Systems). By taking the absolute value of space and rotating it along multiple axes iteratively, we generate complex faceted structures. We use a base SDF of a thin box or plane.

### Mouse Interaction
The mouse acts as a flattening tensor. When the raymarching position `p` is near `mousePos`, the space-folding iterations are smoothly interpolated back to zero, flattening the origami into a simple plane that reflects the surrounding void.

### Color Mapping / Shading
The surface uses a physical-based thin-film interference approximation. We calculate the view angle (dot product of normal and view direction) and use it to sample a procedurally generated spectrum, adding intense emissive highlights on the sharp edges (where `length(p) < edge_threshold`).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Quantum Aether-Origami
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// --- Core SDFs & KIFS Folding ---
fn fold(p: vec3<f32>, normal: vec3<f32>, distance: f32) -> vec3<f32> {
    let t = dot(p, normal) - distance;
    return p - 2.0 * min(0.0, t) * normal;
}

fn map(p: vec3<f32>) -> f32 {
    var q = p;
    // Iterative KIFS folding logic
    // ...
    // Base structure (e.g., thin box)
    return length(max(abs(q) - vec3<f32>(1.0, 1.0, 0.05), vec3<f32>(0.0))) - 0.01;
}

// --- Main Render Loop ---
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let texSize = textureDimensions(writeTexture);
    let uv = vec2<f32>(id.xy) / vec2<f32>(texSize);

    // Raymarching, Mouse Flattening, and Audio pulse integration using u.config.y
    // ...

    var color = vec4<f32>(0.0);
    textureStore(writeTexture, id.xy, color);
}
```

## Parameters (for UI sliders)
- Fold Complexity (5.0, 1.0, 10.0, 1.0)
- Crease Glow (1.5, 0.0, 5.0, 0.1)
- Audio Reactivity (1.0, 0.0, 2.0, 0.1)
- Interference Shift (0.5, 0.0, 2.0, 0.05)

## Integration Steps
1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
