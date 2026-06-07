# New Shader Plan: Cymatic Quantum-Silk Loom

## Overview
A majestic, hyper-dimensional loom that weaves strands of luminescent quantum silk into complex, fluid-like cymatic geometries driven by the rhythm of unseen cosmic frequencies.

## Features
- Infinite, flowing ribbons of luminescent, translucent quantum silk.
- Complex interference patterns forming cymatic mandalas driven by audio frequencies.
- Soft volumetric lighting that illuminates the silk from within.
- Dynamic color blending transitioning across iridescent neon spectra (magenta, cyan, gold).
- Fluid-like wave dynamics that warp the fabric in response to low-end bass thumps.

## Technical Implementation
- File: public/shaders/gen-cymatic-quantum-silk-loom.wgsl
- Category: generative
- Tags: ["organic", "quantum", "abstract", "flowing", "cymatic"]
- Algorithm: Raymarching with signed distance fields for ribbons and 3D domain warping using noise and trigonometric interference patterns.

### Core Algorithm
The environment is built using raymarching. The silk ribbons are modeled as domain-warped planes or ribbons, modulated by a combination of high-frequency sine waves (cymatics) and low-frequency FBM noise (fluid flow). Smooth-min operations blend overlapping silk structures, and temporal phase shifts drive the weaving motion.

### Mouse Interaction
Mouse movement functions as a gravitational "shuttle" on the loom, pinching and twisting the nearby silk threads into a temporary vortex that follows the cursor.

### Color Mapping / Shading
The shading utilizes thin-film iridescence approximations based on the viewing angle and surface normal. Colors shift through a neon spectrum depending on the audio frequency bands, with subsurface scattering for a soft, glowing, translucent look.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Cymatic Quantum-Silk Loom
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>
};

// ... (full skeleton with comments)
```

## Parameters (for UI sliders)
- Silk Density: `u.zoom_params.x` (0.5, 0.1, 1.0, 0.01)
- Cymatic Frequency: `u.zoom_params.y` (1.0, 0.1, 5.0, 0.1)
- Luminescence: `u.zoom_params.z` (0.8, 0.0, 2.0, 0.05)

## Integration Steps
- Create shader file
- Create JSON definition
- Run generate_shader_lists.js
- Upload via storage_manager
