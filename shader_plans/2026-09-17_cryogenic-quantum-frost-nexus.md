# New Shader Plan: Cryogenic Quantum-Frost Nexus

## Overview
A relentless, infinitely expanding subzero lattice where supercooled quantum fluids freeze and shatter in algorithmic rhythm, weaving a crystalline hyper-structure of pristine ice and ethereal blue energy. It feels like gazing into the core of a frozen cosmic supercomputer computing its final breath.

## Features
- Infinitely generating fractal ice crystals utilizing recursive tetrahedral domain folding and sharp SDF intersections.
- Sub-zero fluid dynamics driven by high-frequency fBM noise, simulating vapor and supercooled liquid freezing upon contact with the lattice.
- Audio-reactive crystallization: high hats and treble cause immediate micro-fractures in the ice, while deep bass pulses emit waves of bioluminescent frost-blue energy.
- Mouse-driven "thermal anomaly": the cursor acts as a heat source, melting nearby ice into a chaotic quantum fluid that rapidly refreezes as it moves away.
- Advanced refraction and chromatic dispersion, simulating the optical properties of hyper-dense cosmic ice.
- Volumetric frost haze and localized depth-of-field to sell the icy, dense atmospheric depth.

## Technical Implementation
- File: public/shaders/gen-cryogenic-quantum-frost-nexus.wgsl
- Category: generative
- Tags: ["ice", "quantum", "crystalline", "fractal", "audio-reactive", "raymarching", "refraction"]
- Algorithm: 3D Raymarching through a dynamic composite SDF consisting of a recursively folded tetrahedral lattice (the ice structure) and a fluid volume modified by 4D noise, with mouse-based localized smoothing (melting).

### Core Algorithm
The architecture relies on a highly angular SDF environment generated via recursive space folding (Kaleidoscopic Iterated Function System - KIFS), using tetrahedral symmetry to create sharp, ice-like shards. A secondary fluid SDF, animated via 4D simplex noise and audio data extracted from `extraBuffer`, flows through the gaps. The fluid and ice interact via a boolean difference and smooth min (`smin`) function, giving the illusion of fluid physically freezing onto the structure over time.

### Mouse Interaction
The mouse acts as a localized heat point and gravity well. Distance to the cursor's unprojected 3D coordinate is used to dynamically lower the sharpness of the KIFS folds and apply a localized `smin` blend to the ice structure, physically melting the sharp geometry into a viscous, fluid-like state. As the cursor leaves, the cooling factor takes over, re-hardening the geometry into sharp crystals.

### Color Mapping / Shading
The ice utilizes a complex glass/refraction shader approximation, sampling an abstract icy HDRI and utilizing internal reflection. The color palette spans deep abyssal blues to blinding, pristine cyans and stark whites. The fluid emits a soft, internal luminescent glow (subsurface scattering approximation) that shifts toward pure white upon freezing, creating stark contrast against the dark background void.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Cryogenic Quantum-Frost Nexus
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
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // .xyzw = user params p1..p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    // Boilerplate setup
    let dims = textureDimensions(writeTexture);
    let coord = vec2<i32>(gid.xy);
    if (any(coord >= vec2<i32>(dims))) {
        return;
    }

    // Core raymarching and shading logic goes here
    // ...
}
```

Parameters (for UI sliders)

- zoom_params.x (Lattice Density): 1.0, 0.1, 5.0, 0.1
- zoom_params.y (Frost Intensity): 0.5, 0.0, 1.0, 0.05
- zoom_params.z (Refraction Index): 1.3, 1.0, 2.5, 0.01
- zoom_params.w (Melting Radius): 2.0, 0.5, 5.0, 0.1
