# New Shader Plan: Singularity Forge

## Overview
A hyper-dense, gravity-warped crucible of collapsing stars and chaotic plasma rings, endlessly generating and consuming geometric artifacts.

## Features
- **Accretion Disk Particle System:** Millions of glowing embers swirling into a central black hole void.
- **Gravitational Lensing:** Background starlight heavily distorted around the central singularity.
- **Audio-Reactive Spaghettification:** Frequency-driven stretching and tearing of plasma streams (u.config.y).
- **Hawking Radiation Jets:** High-energy polar beams that pulse with bass hits.
- **Relativistic Time Dilation:** Movement slows exponentially as particles approach the event horizon.
- **Mouse Gravity Well:** The cursor creates a secondary, smaller black hole that pulls and disrupts the main accretion disk.
- **Volumetric Event Horizon:** A completely light-absorbent core ringed by an intensely bright photon sphere.

## Technical Implementation
- File: public/shaders/gen-singularity-forge.wgsl
- Category: generative
- Tags: ["cosmic", "black-hole", "gravity", "plasma", "audio-reactive"]
- Algorithm: Raymarching combined with particle simulation techniques in a compute shader, heavily relying on non-Euclidean space folding (domain distortion) and inverse-square gravity fields.

### Core Algorithm
- **Base SDFs:** A central negative sphere (event horizon) surrounded by a thick, noisy torus (accretion disk).
- **Space Distortion:** Domain warping using the inverse distance to the origin to bend rays, creating gravitational lensing effects.
- **Noise Type:** Simplex noise for plasma turbulence, overlaid with high-frequency Voronoi for glowing embers within the disk.
- **Particle Advection:** While primarily raymarched, the noise field flows inward and accelerates radially toward the singularity, creating a particle-like illusion.

### Mouse Interaction
- The mouse position (mapped to world space) introduces an additional gravity sink.
- Formula: `ray_dir = normalize(ray_dir + (mouse_pos - ray_pos) * (mouse_gravity_strength / pow(distance(ray_pos, mouse_pos), 2.0)))`.

### Color Mapping / Shading
- **Event Horizon:** Pure black (`vec3(0.0)`).
- **Photon Sphere:** Extreme bloom, pure white with slight blue chromatic aberration.
- **Accretion Disk:** Blackbody radiation color mapping (deep reds/oranges at the edges, shifting to blinding white-blue near the center).
- **Jets:** High-intensity purple/UV glow, mapped to audio amplitude.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Singularity Forge
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// ... SDFs, Noise, and Raymarching Loop ...
```

## Parameters (for UI sliders)
- **Disk Density:** u.zoom_params.x (default 1.0, min 0.1, max 5.0, step 0.1)
- **Jet Intensity:** u.zoom_params.y (default 0.5, min 0.0, max 2.0, step 0.05)
- **Gravity Warp:** u.zoom_params.z (default 1.0, min 0.0, max 3.0, step 0.1)
- **Time Dilation:** u.zoom_params.w (default 1.0, min 0.1, max 2.0, step 0.1)

## Integration Steps
1. Create shader file `public/shaders/gen-singularity-forge.wgsl`
2. Create JSON definition `shader_definitions/generative/gen-singularity-forge.json`
3. Run `node scripts/generate_shader_lists.js`
4. Upload via local `storage_manager`
