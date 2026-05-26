# New Shader Plan: Prismatic Void-Weaver Ouroboros

## Overview
A hyper-dimensional, endlessly twisting serpentine ring forged of chromatic plasma and fractal dark matter that consumes its own geometric tail while weaving a tapestry of light across the void.

## Features
- Infinite Mobius loop geometry acting as the primary ouroboros body.
- Fractal "scales" that shift colors dynamically based on temporal acoustic frequencies.
- Core of absolute darkness that distorts and bends the background chromatic light (gravitational lensing).
- Luminescent void-weaves (energy trails) that are emitted as the ouroboros moves and decays.
- Volumetric plasma aura reacting aggressively to low-frequency audio impulses.
- Self-consuming feedback loop where energy trails are pulled back into the creature's mouth.

## Technical Implementation
- File: public/shaders/gen-prismatic-void-weaver-ouroboros.wgsl
- Category: generative
- Tags: ["ouroboros", "void", "fractal", "plasma", "chromatic", "loop"]
- Algorithm: Raymarching with a twisted torus base SDF, modulated by fBM for organic fractal scales, with a volumetric ray-bending pass for the central void singularity.

### Core Algorithm
- Raymarch a modified torus that twists along its length (Mobius strip).
- Apply a high-frequency multi-octave domain warped noise to the surface SDF to simulate shifting metallic scales.
- Implement a gravitational lensing effect around the center of the torus by bending the view ray towards the origin depending on distance.
- Combine SDFs with smooth min functions for the energy trails that spin around the main body.

### Mouse Interaction
- Mouse X/Y control the spatial origin of the gravitational void, pulling the ouroboros structure towards the cursor like a black hole.
- Distance from mouse to center influences the speed of the self-consuming animation loop.

### Color Mapping / Shading
- Chromatic dispersion on the scales, blending iridescent neon pinks, deep void purples, and quantum blues.
- The void core is pure `#000000` with an emissive rim-light that bleeds into the surrounding geometry.
- Ambient occlusion and soft shadows applied inside the coils to enhance the depth of the endless loop.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Prismatic Void-Weaver Ouroboros
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Twist Density, y=Plasma Glow, z=Void Gravity, w=Audio Reactivity
    ripples: array<vec4<f32>, 50>,
};

// Math constants
const PI: f32 = 3.14159265359;

// Helper functions (rotations, noise)
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(vec2<f32>(c, -s), vec2<f32>(s, c));
}

// Ouroboros SDF
fn sdfOuroboros(p: vec3<f32>, time: f32) -> f32 {
    // Twisted torus logic and scale displacement
    return length(p) - 1.0; // Placeholder
}

// Main raymarching loop and color composition
@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(id.xy) / res;

    // ... Raymarch, void distortion, shading, and texture write ...
}
```

## Parameters (for UI sliders)

Name (default, min, max, step)
- param1 (Twist Density): default 5.0, min 1.0, max 20.0, step 0.5
- param2 (Plasma Glow): default 0.8, min 0.1, max 2.0, step 0.1
- param3 (Void Gravity): default 1.5, min 0.0, max 5.0, step 0.1
- param4 (Audio Reactivity): default 0.5, min 0.0, max 1.0, step 0.05
