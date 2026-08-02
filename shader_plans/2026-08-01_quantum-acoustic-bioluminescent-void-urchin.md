# New Shader Plan: Quantum-Acoustic Bioluminescent Void-Urchin

## Overview
A colossal, undulating deep-space entity composed of hyper-reactive quantum spines and plasma membranes that breathes and dances to sonic vibrations within a zero-g fractal ocean. It merges the microscopic intricacies of deep-sea life with astrophysical phenomena, shimmering in bioluminescent teal, deep violet, and radioactive gold.

## Features
- **Quantum Spine Lattice:** A spherical array of oscillating, needle-like protrusions that continuously assemble and dissipate based on a multi-scale SDF grid.
- **Audio-Reactive Bioluminescence:** The core and spines pulse intensely with bass and mid frequencies, pushing waves of neon chromatic aberration along the lengths of the spines.
- **Plasma Membrane Webbing:** Translucent, fluid-like webbing connecting the spines, simulated via nested sine waves and cellular noise.
- **Gravitational Plankton Swarm:** Orbiting micro-geometry particles (plankton) that are attracted to the urchin's core but repulsed by intense audio peaks.
- **Fluid Void Distortion:** A volumetric, viscous background medium that warps light around the entity (micro-lensing) using raymarched domain distortion.
- **Deep-Void Scattering:** Subsurface scattering and soft shadows that give the urchin a fleshy, organic, yet crystalline appearance.

## Technical Implementation
- File: public/shaders/gen-quantum-acoustic-bioluminescent-void-urchin.wgsl
- Category: generative
- Tags: ["organic", "bioluminescent", "void", "quantum", "oceanic", "audio-reactive"]
- Algorithm: Raymarching combined with polar domain repetition for the spines, 3D Simplex/Voronoi noise for the membrane, and audio-driven SDF displacement.

### Core Algorithm
The central urchin body is constructed using a base sphere SDF combined with a polar domain repetition technique (`atan2` and `length` mappings) to generate hundreds of radiating cones (spines). The lengths and thicknesses of these spines are modulated by a combination of 3D noise and the `plasmaBuffer` audio input, creating a breathing, reacting structure. A secondary SDF, using a smooth minimum (`smin`), creates the webbing between the spines. The entire coordinate space is slowly rotated and warped with a low-frequency curl noise to simulate the viscous ocean void.

### Mouse Interaction
The mouse (`u.zoom_config.yz`) acts as a localized gravity well and energy source. When the cursor approaches the urchin, the spines bend towards the mouse position using a smooth spatial twist/bend function (`p.xy = rot(angle) * p.xy`), and the local bioluminescence intensifies, creating a "touch-reactive" glow effect on the membrane.

### Color Mapping / Shading
The shading model utilizes a combination of Fresnel rim lighting and faux subsurface scattering. The base color is a deep oceanic violet, shifting to intense bioluminescent teal and gold at the tips of the spines and along the membrane edges. Audio reactivity (`plasmaBuffer[0].x`) modulates the emissive output, causing bright flashes of energy to travel outward from the core. A multi-pass raymarching loop accumulates color and opacity to render the translucent volumetric void and the glowing plankton particles.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Quantum-Acoustic Bioluminescent Void-Urchin
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var<storage, read> plasmaBuffer: array<vec4<f32>>;
@group(0) @binding(5) var<storage, read> touchBuffer: array<vec4<f32>>;
@group(0) @binding(6) var<storage, read> layer_1: array<vec4<f32>>;
@group(0) @binding(7) var<storage, read> layer_2: array<vec4<f32>>;
@group(0) @binding(8) var<storage, read> layer_3: array<vec4<f32>>;
@group(0) @binding(9) var depthTexture: texture_depth_2d;
@group(0) @binding(10) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(11) var non_filtering_sampler: sampler;
@group(0) @binding(12) var<storage, read> extraBuffer: array<vec4<f32>>;

struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    frame: u32,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    view_matrix: mat4x4<f32>,
    proj_matrix: mat4x4<f32>,
    camera_pos: vec3<f32>,
    config: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// ... Rotation functions, 3D noise functions, smooth min (smin)

fn map(p: vec3<f32>) -> f32 {
    // Polar repetition for spines
    // Audio displacement from plasmaBuffer
    // Smooth min for membrane webbing
    return 1.0;
}

// Raymarching and shading functions (subsurface scattering, iridescence)
fn render(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) GlobalInvocationID: vec3<u32>) {
    let uv = vec2<f32>(GlobalInvocationID.xy) / u.resolution;
    // ... setup camera, raymarch loop, accumulate color, bloom pass
    textureStore(writeTexture, vec2<i32>(GlobalInvocationID.xy), vec4<f32>(uv, 0.5, 1.0));
}
```

## Parameters (for UI sliders)
- `zoom_params.x`: Spine Density and Length (default: 0.5, min: 0.0, max: 1.0, step: 0.01)
- `zoom_params.y`: Audio Reactivity Multiplier (default: 0.5, min: 0.0, max: 1.0, step: 0.01)
- `zoom_params.z`: Bioluminescence Color Shift (default: 0.5, min: 0.0, max: 1.0, step: 0.01)
- `zoom_params.w`: Void Fluidity / Distortion (default: 0.5, min: 0.0, max: 1.0, step: 0.01)
