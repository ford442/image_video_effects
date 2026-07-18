# New Shader Plan: Luminescent Aether-Plasma Nebula-Koi

## Overview
A hyper-organic, glowing biomechanical space-koi woven from flowing aether-plasma and shattered chromatic crystal, swimming gracefully through a volumetric quantum nebula while reacting dynamically to ambient acoustic frequencies.

## Features
- **Fluid Bio-mechanics:** The koi's body is procedurally generated using twisting tubular SDFs, exhibiting liquid, sinuous movement through cosmic space.
- **Quantum-Plasma Scales:** Glowing iridescent scales composed of layered voronoi noise and sub-surface scattering mimic shattered chrono-glass and plasma.
- **Audio-Reactive Aether Trails:** Ethereal fins and tails emit volumetric light trails that bloom and shatter into particles upon heavy bass drops.
- **Volumetric Nebula Void:** A deep-space, dense particle-storm nebula environment, layered with fractional Brownian motion (fBm) noise.
- **Interactive Gravitational Ripples:** Mouse interactions create fluid ripple distortions and temporal drag through the quantum sea.

## Technical Implementation
- File: public/shaders/gen-luminescent-aether-plasma-nebula-koi.wgsl
- Category: generative
- Tags: ["organic", "quantum", "cosmic", "particle systems", "audio-reactive"]
- Algorithm: Procedural SDF modeling with toroidal and tubular domain warping, volumetric raymarching for the nebula and aether-plasma fields, and audio-driven parameter modulation.

### Core Algorithm
The koi is constructed using a series of blended spherical and tubular SDFs, deformed by sine waves along the local Z-axis to create swimming motion. The scales are produced by overlaying a high-frequency Voronoi pattern with a time-varying metallic gradient. The surrounding nebula employs raymarched volumetric density using 3D Perlin noise and fractional Brownian motion, integrated over multiple steps.

### Mouse Interaction
The mouse cursor acts as a localized gravity well. Its position applies a radial spatial distortion (e.g., `p += normalize(p - mouse) * (1.0 / (1.0 + length(p - mouse)))`) to the domain, bending both the nebula's density field and the koi's aether-trails, creating an interactive fluid-drag effect.

### Color Mapping / Shading
The shader utilizes a rich, high-contrast bioluminescent palette. The core of the koi uses deep liquid-neon blues and cyans, transitioning to bright auroral pinks and purples at the fin edges. A custom bloom pass and subsurface scattering approximation emphasize the ethereal, glowing nature of the plasma scales against the deep dark matter background.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Luminescent Aether-Plasma Nebula-Koi
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
    resolution: vec2<f32>,
    time: f32,
    audio: f32,
    mouse: vec4<f32>,
    zoom_config: vec4<f32>,
    ripples: vec4<f32>,
    // Custom parameters
    plasma_intensity: f32,
    koi_speed: f32,
    nebula_density: f32,
    tail_length: f32,
};

// --- Helper Functions ---
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ... SDFs, noise functions, and main rendering logic ...
```

## Parameters (for UI sliders)

| Name | Default | Min | Max | Step |
|---|---|---|---|---|
| plasma_intensity | 1.0 | 0.0 | 2.0 | 0.01 |
| koi_speed | 1.0 | 0.1 | 5.0 | 0.1 |
| nebula_density | 0.5 | 0.0 | 1.0 | 0.01 |
| tail_length | 1.5 | 0.5 | 3.0 | 0.1 |

## Integration Steps

1. Create shader file `public/shaders/gen-luminescent-aether-plasma-nebula-koi.wgsl`
2. Create JSON definition `shader_definitions/generative/gen-luminescent-aether-plasma-nebula-koi.json`
3. Run `node scripts/generate_shader_lists.js`
4. Upload via storage_manager
