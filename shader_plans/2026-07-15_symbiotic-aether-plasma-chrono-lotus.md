# New Shader Plan: Symbiotic Aether-Plasma Chrono-Lotus

## Overview
A hyper-dimensional, symbiotic cyber-botanical lotus woven from liquid auroral plasma and shattered temporal glass, continuously blooming and collapsing within a dark-matter void while feeding on heavy acoustic bass frequencies.

## Features
- Recursively unfolding geometric petals forged from shimmering chrono-glass.
- A violently pulsating, audio-reactive singularity core that emits liquid-plasma shockwaves.
- Dynamic root-tendrils woven from quantum-fluid that seek out and consume ambient acoustic energy.
- Volumetric aether-fog and dark-matter particle systems swirling around the lotus.
- A temporal feedback loop that causes the petals to visually echo and shatter upon high-frequency sonic impacts.
- Shifting bioluminescent gradients that map deep-sea and cosmic nebulas onto synthetic botanical structures.

## Technical Implementation
- File: public/shaders/gen-symbiotic-aether-plasma-chrono-lotus.wgsl
- Category: generative
- Tags: ["organic", "botanical", "cybernetic", "quantum", "audio-reactive"]
- Algorithm: Raymarching a deeply nested SDF structure for the lotus petals using polar repetition, domain warping, and smooth minimums, combined with a volumetric accumulation pass for the dark-matter void and plasma roots.

### Core Algorithm
The lotus geometry is defined via polar repetition and spherical domain folding of thin, curved box/cylinder SDFs to form petals. The singularity core utilizes a displacement mapped sphere driven by high-frequency fBM and the `plasmaBuffer[0].x` audio reactivity. The roots are created by applying severe domain warping and turbulence to a series of bezier curves. The void uses a volumetric raymarching loop that samples a 3D noise texture mapped to density.

### Mouse Interaction
The viewer's cursor (`u.zoom_config.y` and `u.zoom_config.z`) controls a dual-axis orbital camera, allowing exploration around the blooming lotus, while subtly tilting the gravitational pull of the dark-matter void.

### Color Mapping / Shading
The core heavily features deep ultraviolet and bioluminescent cyan, shifting to glowing auroral greens at the petal tips. The shading model incorporates a glass-like fresnel effect for the petals, intense bloom/glow for the plasma core, and deep volumetric shadows for the void background.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Symbiotic Aether-Plasma Chrono-Lotus
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
```

## Parameters (for UI sliders)
- `u.zoom_params.x`: Petal Unfold State (default 1.0, 0.0, 2.0, 0.05)
- `u.zoom_params.y`: Core Resonance Intensity (default 0.5, 0.0, 3.0, 0.1)
- `u.zoom_params.z`: Aether-Plasma Density (default 1.2, 0.1, 5.0, 0.1)
- `u.zoom_params.w`: Temporal Distortion Rate (default 0.5, 0.0, 2.0, 0.05)
