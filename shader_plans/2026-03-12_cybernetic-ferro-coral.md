# New Shader Plan: Cybernetic Ferro-Coral

## Overview
A biomechanical reef of magnetic, liquid-metal coral that dynamically shapes itself in response to acoustic vibrations, revealing a glowing quantum-plasma core beneath a dark metallic exterior.

## Features
- **Liquid-Metal Growth**: Raymarched structures mimicking coral using domain warping and smooth-min operations to create a fluid, metallic appearance.
- **Audio-Reactive Spikes**: The surface erupts with sharp magnetic spikes (ferrofluid style) synchronized with audio frequencies (`u.config.y`).
- **Quantum Plasma Core**: Deep within the structures, intensely glowing, color-shifting plasma pulses and reveals itself through fissures in the metallic shell.
- **Dynamic Mouse Repulsion**: The magnetic structures react to the user's cursor, aggressively bending and altering their shape as if repelled by a strong magnetic field.
- **Iridescent Thin-Film Shading**: The metallic exterior features a view-dependent color shifting effect (iridescence) similar to oil slicks or oxidized metal.

## Technical Implementation
- File: public/shaders/gen-cybernetic-ferro-coral.wgsl
- Category: generative
- Tags: ["biomechanical", "ferrofluid", "coral", "magnetic", "audio-reactive"]
- Algorithm: Raymarching combining smooth SDFs (spheres, cylinders) with high-frequency noise displacements, and a dual-material shading system (metallic shell vs emissive core).

### Core Algorithm
The scene uses raymarching through a space populated by domain-repeated (`opRep`) base primitives (spheres and thick cylinders) that are heavily blended together using smooth minimums (`smin`). A 3D simplex noise function is added to the SDF distance to create the organic, bumpy coral-like surface. The noise amplitude and frequency are modulated by the audio accumulator (`u.config.y`), causing the surface to grow sharp, ferrofluid-like spikes during energetic moments.

### Mouse Interaction
The `u.mouse` coordinates are mapped to a 3D magnetic repulsor sphere. A localized inverse-distance distortion function is applied to the ray position before evaluating the SDF, gently pushing the coral branches away and flattening the noise spikes in the immediate vicinity of the cursor to simulate magnetic repolarization.

### Color Mapping / Shading
The shading relies on a dual-material approach. The outer surface uses a metallic BRDF approximation with a Fresnel term that drives an iridescent color palette (using cosine-based palettes) to simulate oxidized metal. Where the noise displacement is deepest (valleys and fissures), the material transitions into a high-intensity, emissive quantum plasma, pulsing with vibrant neon colors that contrast sharply against the dark metal.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Cybernetic Ferro-Coral
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// ... (full skeleton with comments)
```

## Parameters (for UI sliders)
- Density (default: 0.5, min: 0.1, max: 2.0, step: 0.1)
- Spike Intensity (default: 1.0, min: 0.0, max: 3.0, step: 0.1)
- Core Glow (default: 1.5, min: 0.5, max: 5.0, step: 0.1)
- Iridescence (default: 1.0, min: 0.0, max: 2.0, step: 0.1)

## Integration Steps
- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
