# New Shader Plan: Celestial Glass-Tornado

## Overview
A colossal, self-contained vortex of hyper-refractive shards suspended in a cosmic void, endlessly shattering and reforming into intricate geometric storm-cells driven by the beat of the universe.

## Features
- **Hyper-Refractive Core:** A central tornado structure composed of millions of tiny, raymarched glass shards.
- **Audio-Reactive Turbulence:** The vortex expands, contracts, and violently twists in sync with audio frequency (`u.config.y`).
- **Chromatic Dispersion Shadows:** Light passing through the tornado splits into vivid RGB spectrums.
- **Mouse Gravity-Well:** The mouse acts as a localized gravitational anomaly, bending the tornado and pulling shards into an orbit around the cursor.
- **KIFS Debris:** Debris orbiting the main tornado is generated using complex Kaleidoscopic Iterated Function Systems.
- **Domain Repetition Void:** The background is an endless, repeating domain of faint, glowing stellar embers.

## Technical Implementation
- File: public/shaders/gen-celestial-glass-tornado.wgsl
- Category: generative
- Tags: ["vortex", "refractive", "glass", "tornado", "kifs", "chromatic", "audio-reactive"]
- Algorithm: Raymarching with heavily domain-warped sweeping splines and KIFS-generated debris, utilizing pseudo-volumetric accumulation for chromatic shadows.

### Core Algorithm
The shader will use raymarching to render the central tornado. The main shape is a twisted cylinder, distorted using multiple octaves of Simplex noise and domain warping based on height (y-axis) and time. The debris field is created by instancing small KIFS structures using domain repetition, masked by a smooth radial falloff from the vortex center.

### Mouse Interaction
The mouse (`u.zoom_config.y`, `u.zoom_config.z`) dictates the center of a strong gravitational pull. As rays pass near the mouse coordinates in world space, their trajectories are warped towards the point, creating a lensing effect, and the KIFS debris is swept into a tight, swirling orbit around the anomaly.

### Color Mapping / Shading
The tornado shards will use a pseudo-refraction model, blending the background stellar embers with a bright, iridescent rim light. Chromatic aberration is simulated by taking multiple slightly offset color samples along the normal of the shards, mapping X/Y/Z offsets to R/G/B channels.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Celestial Glass-Tornado
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
    zoom_params: vec4<f32>,  // UI Sliders mapped here
    ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    // ... Implementation
}
```

Parameters (for UI sliders)

Vortex Twist (1.0, 0.0, 5.0, 0.1)
Debris Density (0.5, 0.0, 1.0, 0.05)
Chromatic Split (0.2, 0.0, 1.0, 0.01)
Audio Reactivity (1.0, 0.0, 2.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "[YYYY-MM-DD]_[slug].md" "[Catchy Title]"
Reply with only: "✅ Plan created and queued: [YYYY-MM-DD]_[slug].md"
