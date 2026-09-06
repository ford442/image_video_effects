# New Shader Plan: Aetherial Plasma Loom

## Overview
A majestic, interwoven tapestry of living plasma threads that gently undulate and twist through an ethereal volume, reacting to ambient energy fields. The aesthetic is surreal, flowing, and deeply luminous, evoking the delicate weaving of light within a cosmic nebula.

## Features
- Intricate 3D ribbons woven by domain-warped fractional Brownian motion.
- Subsurface-like scattering and smooth volumetric luminescence.
- Real-time gravity wells responding dynamically to the mouse position.
- Iridescent color mapping that shifts based on thread density and viewing angle.
- Temporal anti-aliasing and slow structural decay for smooth evolution.

## Technical Implementation
- File: public/shaders/gen-aetherial-plasma-loom.wgsl
- Category: generative
- Tags: ["plasma", "volumetric", "organic", "weaving", "surreal", "fbm", "luminescent"]
- Algorithm: Raymarching through domain-warped noise fields with iterative accumulation to simulate volumetric plasma threading.

### Core Algorithm
The space is defined by a continuous volumetric SDF representing a swirling vortex of ribbons.
This base SDF is distorted intensely using 3D fractional Brownian motion (fBM) with 4-5 octaves, effectively pulling and twisting the base geometry into thin, ribbon-like structures.
A raymarching loop will integrate density through this distorted space. At each step, instead of finding a solid surface, it accumulates a tiny density value whenever the distance is small enough.
The background incorporates a subtle ambient glow based on ray direction.

### Mouse Interaction
The mouse acts as an attractor, warping the domain around its projected 3D position in the scene.
`vec3 mouse_pos = vec3((u.zoom_config.y - 0.5) * 2.0, -(u.zoom_config.z - 0.5) * 2.0, 0.0);`
The distance to `mouse_pos` applies a strong, localized rotation and pulling effect (gravity well) to the base coordinates before they are passed into the fBM noise evaluation, twisting the plasma threads into a vortex when the mouse is pressed.

### Color Mapping / Shading
Color is mapped primarily using a spectral palette function (cosine-based gradient).
The input to the palette is the accumulated density along the ray combined with the local fBM value.
Lower densities emit deep blues and purples, while high density cores shift to brilliant cyan and gold.
Fake subsurface scattering is achieved by tinting the edges of the density regions more strongly with warm colors before the alpha channel fully opacifies.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Aetherial Plasma Loom
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
  zoom_params: vec4<f32>,  // .x = Density, .y = Flow Speed, .z = Twist, .w = Core Brightness
  ripples: array<vec4<f32>, 50>,
};

// ... constants and helpers

fn hash13(p3: vec3<f32>) -> f32 {
    var p = fract(p3 * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

// 3D Noise and fBM
// ...

fn map(p: vec3<f32>) -> f32 {
    // Distance to base swirling ribbons
    // Apply mouse distortion
    // Add fBM domain warping
    // Return distance
    return 0.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let uv = vec2<f32>(f32(id.x) / u.config.z, f32(id.y) / u.config.w);
    let base_uv = uv;
    // clip space correction
    let aspect = u.config.z / u.config.w;
    let clip = (uv * 2.0 - 1.0) * vec2<f32>(aspect, 1.0);

    // Raymarching setup

    // Density integration loop

    // Color mapping

    // Write out
    textureStore(writeTexture, id.xy, final_color);
}
```

Parameters (for UI sliders)
- Density (1.0, 0.1, 3.0, 0.1)
- Flow Speed (0.5, 0.0, 2.0, 0.1)
- Twist (1.5, 0.0, 5.0, 0.1)
- Core Brightness (1.2, 0.5, 3.0, 0.1)
