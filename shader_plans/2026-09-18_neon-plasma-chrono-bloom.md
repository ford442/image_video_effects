# New Shader Plan: Neon Plasma Chrono-Bloom

## Overview
A hyper-vibrant, time-dilated explosion of neon plasma tendrils that bloom and interlace like a digital, cyberpunk flora.

## Features
- Intricate volumetric plasma rays intersecting in 3D space
- Chrono-distortion waves that locally alter the flow of time
- Bioluminescent neon color palettes oscillating between electric pink, cyan, and deep purple
- Interactive gravity wells that pull and twist the plasma fields
- Procedural bloom and heavy light dispersion based on local density
- Fractal noise-driven particle scattering acting as glowing pollen

## Technical Implementation
- File: public/shaders/gen-neon-plasma-chrono-bloom.wgsl
- Category: generative
- Tags: ["plasma", "neon", "volumetric", "cyberpunk", "bloom"]
- Algorithm: Raymarching through a domain-warped 3D noise field with temporal phase shifting

### Core Algorithm
The core utilizes a multi-octave 3D Simplex noise to generate a continuous density field, creating the illusion of gaseous plasma. Domain repetition is applied with smooth minimums to create branching tendril structures. The distance field incorporates a time-varying phase, producing expanding and contracting "bloom" cycles. Raymarching accumulates density along the view ray to calculate final volumetric opacity and emission.

### Mouse Interaction
The mouse acts as a localized time-dilation and gravity node. Based on `zoom_config.yz`, a spherical area of effect is created where the progression of `config.x` (time) is non-linearly shifted, causing the plasma tendrils to swirl and slow down around the cursor. The gravitational pull dynamically distorts the domain repetition boundaries, pulling tendrils into the cursor's orbit.

### Color Mapping / Shading
A high-contrast cosine-based gradient palette maps the accumulated raymarched density to neon colors (electric pinks to deep cyans). Self-illumination (bloom) is simulated by boosting the exposure exponent on high-density areas, and an artificial sub-surface scattering effect is approximated using the gradient of the density field to create glowing edges.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Neon Plasma Chrono-Bloom
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

// ... (full skeleton with comments)
```

Parameters (for UI sliders)

Intensity (0.5, 0.0, 1.0, 0.01) - mapped to zoom_params.x
Distortion Speed (1.0, 0.1, 3.0, 0.1) - mapped to zoom_params.y
Bloom Threshold (0.7, 0.0, 1.0, 0.05) - mapped to zoom_params.z
Hue Shift (0.0, 0.0, 1.0, 0.01) - mapped to zoom_params.w