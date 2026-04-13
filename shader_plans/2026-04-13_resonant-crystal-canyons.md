# New Shader Plan: Resonant Crystal-Canyons

## Overview
An infinite, procedural canyon constructed entirely from highly refractive, glowing crystals where sound waves manifest as visible ripples of chromatic dispersion, flowing like rivers of light through the jagged terrain.

## Features
- Endless procedural crystal terrain utilizing domain-warped FBM and SDFs.
- Audio-reactive crystal growth and rhythmic pulsation mapped to `u.config.y`.
- Advanced chromatic dispersion simulating light bending through colossal bismuth-like structures.
- Viscous rivers of bioluminescent quantum plasma carving dynamically through the canyon floor.
- Interactive camera controls: Mouse inputs sweep the viewpoint and locally warp the crystalline geometries.

## Technical Implementation
- File: public/shaders/gen-resonant-crystal-canyons.wgsl
- Category: generative
- Tags: ["crystal", "landscape", "audio-reactive", "dispersion", "fractal"]
- Algorithm: Raymarching through domain-warped procedural SDF terrain with iterative chromatic dispersion and organic plasma rivers.

### Core Algorithm
Raymarching is employed to map a vast terrain using 3D Fractional Brownian Motion (FBM) intertwined with sharp-edged, boolean-subtracted Signed Distance Fields (SDFs). Infinite domain repetition extends the canyon along the Z-axis, while smooth-min operations blend the jagged crystal walls into a glowing riverbed of fluid plasma.

### Mouse Interaction
The user's mouse position (`u.zoom_config.y`, `u.zoom_config.z`) dictates the panoramic sweep of the camera and creates localized "shattering" deformations in the SDFs, simulating gravity wells or gravitational lensing on the crystal peaks.

### Color Mapping / Shading
A sophisticated material system employing thin-film interference formulas and chromatic aberration. Shadow and ambient occlusion passes emphasize the sharp geometric folds, while the deep ravines emit intense volumetric glow driven by sound (`u.config.y`).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Resonant Crystal-Canyons
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // mapped to UI sliders
    ripples: array<vec4<f32>, 50>,
};

// ... (full skeleton with comments)
fn map(p: vec3<f32>) -> f32 {
    // Placeholder for SDF crystal canyon logic
    return length(p) - 1.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let texSize = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(id.xy) / texSize;
    if (uv.x > 1.0 || uv.y > 1.0) { return; }

    // Raymarching and shading logic here
    var col = vec4<f32>(0.0);
    textureStore(writeTexture, vec2<i32>(id.xy), col);
}
```

## Parameters (for UI sliders)

Crystal Density (0.5, 0.1, 1.0, 0.05) - Mapped to u.zoom_params.x
Plasma Glow (0.8, 0.0, 2.0, 0.1) - Mapped to u.zoom_params.y
Refractive Index (1.5, 1.0, 2.5, 0.05) - Mapped to u.zoom_params.z
Audio Reactivity (1.0, 0.0, 3.0, 0.1) - Mapped to u.zoom_params.w

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-04-13_resonant-crystal-canyons.md" "Resonant Crystal-Canyons"
Reply with only: "✅ Plan created and queued: 2026-04-13_resonant-crystal-canyons.md"
