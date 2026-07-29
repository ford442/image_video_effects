# New Shader Plan: Vitreous Quantum-Lotus Singularity

## Overview
A hyper-dimensional, translucent crystalline lotus flower continuously blooming and fracturing around a gravitational singularity, its fluid-glass petals channeling intense, audio-reactive cosmic energy.

## Features
- **Fractal Blooming Geometry:** Infinite unfolding of layered, vitreous petals generated via iterated smooth-min SDF folds and radial repetition.
- **Gravitational Singularity Core:** A central, distorting void that bends light and pulls the innermost petals into an event horizon.
- **Refractive Chromatic Glass:** Hyper-realistic index of refraction shading with spectral dispersion across the overlapping crystalline petals.
- **Audio-Reactive Luminescence:** Liquid energy pulses traveling radially outward through the petal veins, heavily driven by sub-bass frequencies.
- **Quantum Dust Starlight:** A swirling volumetric nebula of glowing particulate matter caught in the orbit of the lotus.
- **Spacetime Distortion:** Complex spatial warping that continuously rotates and folds the domain to simulate higher-dimensional blooming.

## Technical Implementation
- File: public/shaders/gen-vitreous-quantum-lotus-singularity.wgsl
- Category: generative
- Tags: ["organic", "quantum", "cosmic", "fractal", "flower", "refraction", "audio-reactive"]
- Algorithm: Advanced raymarching utilizing polar domain folding, recursive smooth-min blending for fractal petals, and volumetric scattering.

### Core Algorithm
The lotus structure is achieved by chaining polar coordinate domain repetitions (using `atan2` and `length`) combined with trigonometric folding to create overlapping petal SDFs. The singularity is a dense volumetric sphere with extreme spatial distortion (`p = p * (1.0 + (strength / length(p)))`) applied to surrounding rays. Quantum dust is modeled using 3D value noise sampled along the ray path.

### Mouse Interaction
Mouse input (`let mouse = u.zoom_config.yz;`) shifts the gravitational epicenter of the singularity. The formula translates the base origin of the polar folding: `p -= vec3<f32>(mouse.x * 3.0, mouse.y * 3.0, 0.0)`, causing the entire lotus structure to orbit and bend its petals toward the user's cursor while dynamically warping the refraction index.

### Color Mapping / Shading
The shader uses a multi-layered physically based approximation for the vitreous petals, featuring low diffuse and high specular components mixed with a customized fake refraction calculation. Chromatic aberration is simulated by offsetting the ray march for RGB channels slightly based on the normal. Emissive neon-magenta and liquid-gold accents are scaled directly by `plasmaBuffer[0].x` for intense audio reactivity.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Vitreous Quantum-Lotus Singularity
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var<storage, read> plasmaBuffer: array<vec4<f32>>;
@group(0) @binding(5) var<storage, read> touchBuffer: array<vec4<f32>>;
@group(0) @binding(6) var<storage, read> extraBuffer: array<vec4<f32>>;
@group(0) @binding(7) var non_filtering_sampler: sampler;
@group(0) @binding(8) var readDepthTexture: texture_2d<f32>;

// ... [Uniforms and helper structs] ...

// [Raymarching Map Function]
fn map(p: vec3<f32>) -> f32 {
    // Polar folding and smooth-min lotus petals
    return d;
}

// [Main Compute Shader]
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // Ray setup, intersection, and coloring
}
```

## Parameters (for UI sliders)
- **Petal Complexity** (default: 5.0, min: 1.0, max: 10.0, step: 1.0) mapped to `zoom_params.x`
- **Singularity Mass** (default: 1.5, min: 0.1, max: 5.0, step: 0.1) mapped to `zoom_params.y`
- **Refraction Index** (default: 1.33, min: 1.0, max: 2.5, step: 0.01) mapped to `zoom_params.z`
- **Audio Pulse Glow** (default: 1.0, min: 0.0, max: 3.0, step: 0.1) mapped to `zoom_params.w`
