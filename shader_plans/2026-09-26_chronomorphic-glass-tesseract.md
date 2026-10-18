# New Shader Plan: Chronomorphic Glass Tesseract

## Overview
A hyper-dimensional glass-like structure that morphs through time, capturing light in internal reflections while audio-reactive elements shatter and rebuild its crystalline facets. The aesthetic is a blend of sacred geometry and high-tech quantum computing, glowing with deep luminous auras.

## Features
- Infinite folding tesseract geometry utilizing recursive space transformations.
- Audio-reactive structural shattering and dynamic reassembly.
- Complex internal glass refraction and chromatic dispersion.
- Time-based dimensional rotation with smooth interpolation.
- Deep neon-infused subsurface scattering for organic glow.
- Mouse-interactive gravity wells that distort the space-time fabric around the geometry.

## Technical Implementation
- File: public/shaders/gen-chronomorphic-glass-tesseract.wgsl
- Category: generative
- Tags: ["quantum", "glass", "tesseract", "audio-reactive", "hyper-dimensional", "refraction"]
- Algorithm: Raymarching an unfolded hypercube (tesseract) signed distance field with recursive space folding, enhanced by multi-pass refraction and chromatic aberration accumulation.

### Core Algorithm
The base structure is built using a signed distance field for a 4D hypercube projected into 3D space. Recursive `abs()` folds and rotational matrices (driven by time) create the complex internal structure. Audio data modulates the scale and rotation speed, while sharp noise functions induce micro-fractures in the SDF.

### Mouse Interaction
The mouse cursor acts as a localized gravity well. The space around the mouse position applies a spherical distortion to the raymarching domain, bending rays toward the cursor using a smooth inverse-square falloff formula.

### Color Mapping / Shading
Shading employs an intricate multi-layer material model: a base glass surface with intense specular highlights, volumetric absorption based on ray travel depth to simulate subsurface scattering, and chromatic dispersion calculated by offset ray steps for RGB channels. Colors transition smoothly between deep quantum blues, striking purples, and hot neon pinks.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Chronomorphic Glass Tesseract
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// --- CORE UTILITIES ---
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// --- SDF & ALGORITHM ---
fn map(pos: vec3<f32>, time: f32) -> f32 {
    var p = pos;
    // Mouse distortion
    let mouseDist = length(p.xy - (u.config.xy * 2.0 - 1.0));
    p *= 1.0 + 0.5 * exp(-mouseDist * 2.0) * u.zoom_params.w;

    // Recursive space folding
    for (var i = 0; i < 4; i++) {
        p = abs(p) - vec3<f32>(0.5 + sin(time * 0.2) * 0.2);
        let r = rot(time * 0.1 + f32(i));
        let pxy = r * p.xy;
        p = vec3<f32>(pxy.x, pxy.y, p.z);
    }

    return length(max(abs(p) - vec3<f32>(1.0), vec3<f32>(0.0))) - 0.1;
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }
    let uv = vec2<f32>(global_id.xy) / vec2<f32>(dims);

    // ... Raymarching, audio modulation from extraBuffer, and color mapping ...

    let color = vec4<f32>(uv.x, uv.y, 1.0, 1.0); // Placeholder
    textureStore(writeTexture, global_id.xy, color);
}
```

Parameters (for UI sliders)

Shatter Intensity (0.5, 0.0, 1.0, 0.01) -> zoom_params.x
Refraction Index (1.33, 1.0, 2.0, 0.01) -> zoom_params.y
Color Shift (0.0, -1.0, 1.0, 0.1) -> zoom_params.z
Mouse Gravity (0.5, 0.0, 1.0, 0.01) -> zoom_params.w