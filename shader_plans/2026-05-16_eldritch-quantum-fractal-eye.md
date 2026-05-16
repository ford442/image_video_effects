# New Shader Plan: Eldritch-Quantum Fractal-Eye

## Overview
A colossal, hyper-dimensional eye constructed from infinitely folding quantum fractals and liquid plasma, constantly shifting its non-Euclidean iris geometry and dilating violently in response to acoustic resonance.

## Features
- **Fractal Spherical Inversion Iris:** An impossibly complex, mutating Mandelbulb-like structure that forms the pupil and iris.
- **Audio-Reactive Dilation:** Bass frequencies trigger violent dilations of the central singularity, warping the surrounding space.
- **Sentient Mouse Tracking:** The colossal eye physically rotates to follow the user's cursor, employing an organic, delayed spring-physics easing.
- **Volumetric God-Rays:** Intense, spectral light beams shoot out from the pupil, creating dense volumetric lighting effects.
- **Plasma-Vein Sclera:** Glowing, Voronoi-based plasma tendrils that branch and pulse radially from the iris out to the edges of the screen.
- **Quantum Blink Anomalies:** Periodic, math-driven visual glitches that simulate an eldritch "blink", momentarily fracturing the spatial coordinates.

## Technical Implementation
- File: public/shaders/gen-eldritch-quantum-fractal-eye.wgsl
- Category: generative
- Tags: ["fractal", "eldritch", "quantum", "eye", "audio-reactive", "neon"]
- Algorithm: Raymarching combined with recursive spherical inversions, mapped over a Voronoi-displaced spherical surface.

### Core Algorithm
- **Raymarching:** Raymarch against a custom SDF representing a warped sphere.
- **Fractal Detail (Iris):** Inside the sphere's SDF, apply recursive folding (KIFS) and spherical inversions (`z = z / dot(z,z)`) to generate the intricate iris ridges.
- **Voronoi Displacements (Sclera):** Apply 3D cellular noise on the outer bounds of the sphere to create the veiny, plasma-filled sclera network.
- **Volumetric Rays:** Accumulate density along the ray path based on distance to the central pupil axis.

### Mouse Interaction
- **Look Mechanics:** Map the mouse coordinates (`u.zoom_config.yz`) to an angular rotation matrix (pitch and yaw).
- **Easing:** Apply a time-based smoothed interpolation to give the eye a heavy, organic, sentient tracking feel rather than instantaneous snapping.
- **Gravity Well:** Clicking (`u.zoom_config.w`) intensely increases the gravitational pull of the pupil, sucking the plasma veins inward.

### Color Mapping / Shading
- **Palette:** Deep abyssal purples, intense bio-luminescent cyans, and aggressive neon magentas.
- **Shading:** Map SDF distances and trap variables to a gradient palette, utilizing `plasmaBuffer` to shift hues based on audio bands.
- **Bloom & Emission:** Apply a post-process glow calculation based on the distance field trap to create the intense volumetric god-rays.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Eldritch-Quantum Fractal-Eye
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

// --- UNIFORMS ---
struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,  // x, y, startTime, unused
};

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(vec2<f32>(c, -s), vec2<f32>(s, c));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(global_id.xy) / res;

    // Mouse tracking setup
    let mouse = u.zoom_config.yz;
    let time = u.config.x;
    let audioBass = plasmaBuffer[0].x;

    // Core raymarching and rendering logic
    let finalColor = vec4<f32>(uv.x, uv.y, audioBass, 1.0);

    textureStore(writeTexture, global_id.xy, finalColor);
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Fractal Iterations (8.0, 1.0, 15.0, 1.0)
- Dilation Intensity (0.5, 0.0, 1.0, 0.01)
- Plasma Vein Density (3.0, 0.1, 10.0, 0.1)
- Color Shift (0.0, -1.0, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-05-16_eldritch-quantum-fractal-eye.md" "Eldritch-Quantum Fractal-Eye"
Reply with only: "✅ Plan created and queued: 2026-05-16_eldritch-quantum-fractal-eye.md"
