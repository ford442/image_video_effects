# New Shader Plan: Ethereal Quantum-Glass Nautilus

## Overview
A majestic, crystalline logarithmic spiral that fractures incoming light into spectral interference patterns while breathing with audio reactivity. It feels like an ancient, fragile deep-sea creature forged from liquid prismatic glass, suspended in an abyssal void.

## Features
- Intricate 3D logarithmic spiral SDF (Nautilus shape).
- Deep raymarching with multiple internal bounces for glass-like refraction.
- Spectral dispersion shading (chromatic aberration) on edges.
- Audio-reactive "breathing": the spiral expands and pulses with low-frequency audio.
- Gravity-well mouse interaction that bends the surrounding space, warping the spiral.
- "Quantum" structural noise that introduces micro-fractures inside the glass volume.

## Technical Implementation
- File: public/shaders/gen-ethereal-quantum-glass-nautilus.wgsl
- Category: generative
- Tags: ["3d", "raymarching", "refraction", "glass", "spiral", "audio-reactive", "mouse-interactive"]
- Algorithm: Raymarching a twisted, logarithmic spiral SDF combined with volumetric chromatic shading and audio-driven domain distortion.

### Core Algorithm
- **SDF Structure:** Base shape is a cone bent into a logarithmic spiral. A polar coordinate domain transformation `atan2` and `length` are used to fold the space.
- **Micro-fractures:** 3D Voronoi noise is subtracted from the SDF at a very high frequency but very low amplitude to simulate internal cracks.
- **Audio Distortion:** Sample `dataTextureC` to modulate the spacing and thickness of the spiral chambers.

### Mouse Interaction
- The mouse position (from `u.zoom_config.yz`) acts as a gravitational lens. Space around the mouse coordinates is curved using an inverse-square distance falloff, creating a warping "black hole" effect on the rays before they hit the SDF.

### Color Mapping / Shading
- Thin-film interference simulation. The angle between the view ray and surface normal calculates a phase shift, driving a cosine palette to produce an iridescent, pearlescent sheen.
- Internal glowing core: Subsurface scattering approximated by accumulating density near the center of the spiral, tinted cyan/magenta.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Ethereal Quantum-Glass Nautilus
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Point Density, .y = Rotation Speed, .z = Point Size, .w = Color Shift
  ripples: array<vec4<f32>, 50>,
};
// ----------------------------------------------------------------

// Add struct, SDF functions, raymarching loop, shading, and main compute entry here...
```

Parameters (for UI sliders)

- Refraction Index (default 1.5, min 1.0, max 2.5, step 0.01)
- Spiral Tightness (default 0.2, min 0.05, max 0.8, step 0.01)
- Iridescence Shift (default 0.5, min 0.0, max 1.0, step 0.05)
- Audio Reactivity (default 1.0, min 0.0, max 3.0, step 0.1)

Integration Steps

1. Create shader file `public/shaders/gen-ethereal-quantum-glass-nautilus.wgsl`
2. Create JSON definition in `shader_lists/`
3. Run `node scripts/generate_shader_lists.js`
4. Upload via storage_manager
