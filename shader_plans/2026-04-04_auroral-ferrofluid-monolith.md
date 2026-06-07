# New Shader Plan: Auroral Ferrofluid-Monolith

## Overview
A colossal, liquid-metal obelisk suspended in a void, its surface rippling with spiky, audio-reactive ferrofluid structures while crackling with volumetric auroral energy.

## Features
- Infinite, gravity-defying ferrofluid spikes driven by audio (`u.config.y`).
- Volumetric auroral plasma streams wrapping around the central monolith.
- Dynamic subsurface scattering on the metallic fluid surface.
- Mouse interaction creates magnetic distortion fields that repel or attract the spikes.
- Chromatic dispersion on the tips of the ferrofluid spikes based on audio frequency.

## Technical Implementation
- File: public/shaders/gen-auroral-ferrofluid-monolith.wgsl
- Category: generative
- Tags: ["ferrofluid", "monolith", "aurora", "liquid-metal", "audio-reactive"]
- Algorithm: Raymarching an SDF capped cylinder with high-frequency domain-warped FBM to simulate magnetic spikes, layered with volumetric raymarching for auroral glow.

### Core Algorithm
- Primary SDF is a tall, slightly tapered monolith (capped cylinder/box).
- Displacement uses a specialized "spike" noise (absolute value of simplex noise, heavily exponentiated) mapped to audio reactivity.
- Volumetric pass steps through an FBM density field to render the glowing aurora bands surrounding the monolith.

### Mouse Interaction
- `u.zoom_config.y` and `u.zoom_config.z` define a magnetic pole. Distance to this pole scales the spike height and twists the aurora bands.

### Color Mapping / Shading
- Deep chrome and metallic reflections for the monolith using Matcap-style normal mapping or calculated specular highlights.
- Iridescent rim lighting for the auroral plasma in cyan, magenta, and neon green.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Auroral Ferrofluid-Monolith
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
    zoom_params: vec4<f32>,  // x=Spike Length, y=Aurora Intensity, z=Magnetic Twist, w=Fluid Metallic
    ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    // ... rest of implementation
}
```

## Parameters (for UI sliders)

Name (default, min, max, step)
- Spike Length (0.5, 0.0, 1.0, 0.01)
- Aurora Intensity (0.8, 0.0, 2.0, 0.01)
- Magnetic Twist (0.3, 0.0, 1.0, 0.01)
- Fluid Metallic (0.9, 0.0, 1.0, 0.01)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-04-04_auroral-ferrofluid-monolith.md" "Auroral Ferrofluid-Monolith"
Reply with only: "✅ Plan created and queued: 2026-04-04_auroral-ferrofluid-monolith.md"
