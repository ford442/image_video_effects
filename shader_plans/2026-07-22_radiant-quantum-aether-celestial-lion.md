# New Shader Plan: Radiant Quantum-Aether Celestial-Lion

## Overview
A hyper-majestic, biomechanical celestial lion woven from radiant quantum-aether and shattered auroral plasma, prowling gracefully through a collapsing particle-storm void while its shimmering mane bursts into chromatic fractals.

## Features
- Deep, volumetric, raymarched biomechanical lion anatomy (metallic structure, sleek cybernetic plating).
- Shimmering, fluid-plasma mane created through overlapping, noise-disturbed SDF geometries that react organically to time.
- Heavy acoustic audio reactivity: the core of the lion pulsates violently to sub-bass, and the mane fractals ripple with high-frequency audio data.
- Ethereal particle-storm void background rendering using multi-octave domain repetition.
- Holographic chromatic aberration and subsurface scattering algorithms to emulate liquid quantum-aether textures.
- Interactive mouse gravity: the lion's mane and surrounding particle storm warp dynamically toward the mouse anomaly coordinates.

## Technical Implementation
- File: public/shaders/gen-radiant-quantum-aether-celestial-lion.wgsl
- Category: generative
- Tags: ["lion", "animal", "quantum", "aether", "plasma", "volumetric", "fractal", "audio-reactive"]
- Algorithm: Raymarching combined with domain-repetition (`modc`), simplex noise distortion, and volumetric color accumulation.

### Core Algorithm
The shader maps the 3D space using SDFs. The lion's body consists of smooth-blended (`opSmoothUnion`) ellipsoids and capsules. The mane is constructed from a radial array of curved planes, disturbed by a 3D simplex noise function. The void background involves stepping through an accumulated noise field completely bypassing the primary raymarching hit to act as an infinite spatial volume.

### Mouse Interaction
The mouse (via `u.zoom_config.yz`) acts as a gravitational spacetime anomaly. The 3D position vector `p` is offset before SDF evaluation: `p -= vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0)`. Furthermore, a twisting matrix is applied proportionally to the distance from the mouse anomaly to give a physical warp effect.

### Color Mapping / Shading
The shading model blends physically-based reflections with intense bloom mapping. Deep indigo and quantum-blue serve as the base structure, transitioning to blistering gold and liquid magenta in the mane. Audio reactivity (`plasmaBuffer[0].x` for bass, `plasmaBuffer[1].x` for highs) modulates the emission intensity and the scale of the chromatic fractals directly in the pixel shading phase.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Radiant Quantum-Aether Celestial-Lion
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Mane Density, y=Plasma Glow, z=Fractal Complexity, w=Void Turbulence
    ripples: array<vec4<f32>, 50>,
};

// ... (Utility functions: rot2D, noise, smooth_min)

fn map(p: vec3<f32>) -> vec2<f32> {
    var p_warp = p;
    // Mouse warp implementation
    let mouse = u.zoom_config.yz;
    p_warp -= vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0);

    // Geometry modeling...
    return vec2<f32>(1.0, 0.0);
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    // Standard raymarching loop
    return vec2<f32>(0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }
    let uv = vec2<f32>(f32(id.x) / f32(dimensions.x), f32(id.y) / f32(dimensions.y));

    // Core pixel calculation logic...
    textureStore(writeTexture, vec2<i32>(i32(id.x), i32(id.y)), vec4<f32>(uv, 0.0, 1.0));
}
```

Parameters (for UI sliders)

Mane Density (0.6, 0.1, 1.5, 0.01)
Plasma Glow (0.8, 0.0, 2.0, 0.05)
Fractal Complexity (0.5, 0.0, 1.0, 0.05)
Void Turbulence (0.4, 0.0, 1.0, 0.01)
