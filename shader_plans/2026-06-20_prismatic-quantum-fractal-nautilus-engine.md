# New Shader Plan: Prismatic Quantum-Fractal Nautilus-Engine

## Overview
A hyper-organic, spiraling biomechanical nautilus shell forged from prismatic quantum glass and auroral plasma, endlessly unfurling within a deep-space nebula while reacting explosively to ambient acoustic frequencies.

## Features
- **Quantum Shell Geometry:** Procedural generation of a spiraling nautilus structure using logarithmic spirals and toroidal SDFs.
- **Prismatic Glass Refraction:** Multi-layered chromatic dispersion and inner glow mimicking refractive quantum glass.
- **Audio-Reactive Core:** A fiercely glowing auroral plasma core that surges with energy during bass drops.
- **Fractal Inner Chambers:** Endlessly recursive geometric chambers scaling inwards logarithmically.
- **Cosmic Nebula Environment:** Volumetric deep-space plasma dust that interacts and bends around the nautilus' gravity well.
- **Temporal Distortion:** Smooth temporal manipulation of the spiral's unfolding animation based on elapsed time.

## Technical Implementation
- File: public/shaders/gen-prismatic-quantum-fractal-nautilus-engine.wgsl
- Category: generative
- Tags: ["organic", "quantum", "fractal", "nautilus", "cosmic", "audio-reactive"]
- Algorithm: Raymarching combined with domain repetition mapped to a logarithmic spiral, utilizing custom noise and SDFs for organic mechanical geometry.

### Core Algorithm
Employs raymarching with a primary distance function structured around a 3D logarithmic spiral curve. Domain warping and folding are used to generate the recursive inner chambers, combined with smooth minimums (`smin`) to blend the biological curves with intricate, hard-surface mechanical greebles.

### Mouse Interaction
The mouse acts as a localized gravity manipulator. Dragging causes the fractal chambers to dilate and the outer shell to warp dynamically towards the interaction point. The distortion formula utilizes an inverse-square attenuation: `distortion = max(0.0, 1.0 - length(p.xy - mouse_pos) / radius) * power;`.

### Color Mapping / Shading
Materials feature complex subsurface scattering approximations and iridescence based on view angle and normal dot products. The glowing core and aether plasma trails use volumetric density accumulation, colored with shifting chromatic gradients that cycle over time and audio intensity.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Prismatic Quantum-Fractal Nautilus-Engine
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
- **Aura Intensity:** (0.5, 0.0, 1.0, 0.01) - Controls the brightness of the glowing core.
- **Spiral Expansion:** (1.2, 0.5, 2.0, 0.05) - Adjusts the tightness of the logarithmic spiral.
- **Fractal Depth:** (3.0, 1.0, 6.0, 1.0) - Number of recursive inner chamber iterations.
- **Audio Reactivity:** (0.8, 0.0, 2.0, 0.05) - Multiplier for acoustic resonance effects.

## Integration Steps
1. Create shader file `public/shaders/gen-prismatic-quantum-fractal-nautilus-engine.wgsl`
2. Create JSON definition `shader_definitions/generative/gen-prismatic-quantum-fractal-nautilus-engine.json`
3. Run `node scripts/generate_shader_lists.js`
4. Upload via storage_manager
