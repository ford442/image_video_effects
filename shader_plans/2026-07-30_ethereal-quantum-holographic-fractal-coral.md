# New Shader Plan: Ethereal Quantum-Holographic Fractal-Coral

## Overview
A majestic, deep-void cybernetic coral reef that self-assembles through quantum superposition, weaving holographic bio-luminescence with hyper-geometric fractal branches.

## Features
- **Quantum Spore Generation:** Swarming particle-like coral spores that crystallize into fractal branches upon collision with invisible SDF volumes.
- **Holographic Bio-luminescence:** Ethereal, shifting chromatic interference patterns that give the coral a spectral, translucent appearance.
- **Audio-Reactive Symbiosis:** The coral branches pulsate with liquid neon energy driven by audio frequencies, expanding the fractal recursion depth on bass hits.
- **Fluid Void Dynamics:** A dense, viscous aether environment that warps light around the coral, creating localized micro-lensing effects.
- **Self-Assembling Geometry:** Continuous morphing and growing via raymarched KIFS (Kaleidoscopic Iterated Function Systems) combined with cellular noise.
- **Deep Void Shading:** High-contrast void background with volumetric fog that scatters the holographic light emitted by the coral structure.

## Technical Implementation
- File: public/shaders/gen-ethereal-quantum-holographic-fractal-coral.wgsl
- Category: generative
- Tags: ["organic", "quantum", "holographic", "fractal", "coral", "oceanic", "audio-reactive"]
- Algorithm: Raymarching through KIFS fractals modulated by 3D cellular/Voronoi noise for organic growth patterns, combined with volumetric light scattering.

### Core Algorithm
The coral structure is modeled using a KIFS (Kaleidoscopic Iterated Function System) fractal algorithm to generate recursive branching. This geometric precision is softened and made organic by blending it (using smooth min/max operations) with a 3D cellular/Voronoi noise field. The recursion depth and folding scales are dynamically modulated by time and audio input to simulate growth and pulsing. The surrounding aether is simulated with volumetric ray marching to calculate light scattering and micro-lensing (refraction) based on proximity to the coral.

### Mouse Interaction
Mouse movement (`let mouse = u.zoom_config.yz;`) acts as an attractive "bio-luminescent lure" in the void. It distorts the local space of the fractal, pulling branches towards the cursor `p -= vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0) * exp(-length(p) * 0.5);` and intensifying the holographic chromatic aberration near the interaction point.

### Color Mapping / Shading
The shading employs a custom holographic iridescent material model. It calculates color based on the viewing angle (fresnel) and local surface curvature (derived from the SDF normal), mapped through a multi-frequency sine wave palette to produce interference patterns. Audio reactivity (`plasmaBuffer[0].x`) directly injects emissive energy bursts into the fractal iterations, lighting up the internal structure with neon cyan and magenta pulses that scatter into the surrounding volumetric fog.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Ethereal Quantum-Holographic Fractal-Coral
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

// [3D Cellular Noise & KIFS Fractal Fold]
fn map(p: vec3<f32>) -> f32 {
    // KIFS fractal logic combined with voronoi/cellular noise blending
    return d;
}

// [Holographic Material and Volumetric Scattering]
fn render(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    // Raymarching loop, normal calculation, fresnel interference
    return col;
}

// [Main Compute Shader]
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // Ray setup, intersection, and coloring
}
```

## Parameters (for UI sliders)
- **Fractal Density** (default: 3.0, min: 1.0, max: 8.0, step: 0.1) mapped to `zoom_params.x`
- **Holographic Frequency** (default: 5.0, min: 1.0, max: 20.0, step: 0.5) mapped to `zoom_params.y`
- **Bio-Luminescence Intensity** (default: 1.2, min: 0.0, max: 3.0, step: 0.1) mapped to `zoom_params.z`
- **Audio Pulse Propagation** (default: 2.0, min: 0.5, max: 5.0, step: 0.1) mapped to `zoom_params.w`
