# New Shader Plan: Luminescent Aether-Plasma Astro-Axolotl

## Overview
A hyper-dimensional, cyber-organic celestial axolotl drifting gracefully through a fluid-dynamic quantum nebula, its external gills blooming like bioluminescent plasma-corals reacting violently to acoustic frequencies.

## Features
- Intricate, organic-mechanical axolotl anatomy (translucent body, floating tail fin, radiant branching gills) rendered via advanced raymarching and smooth-min operations.
- Bioluminescent external gills that behave like chaotic fractal trees, dynamically expanding and shifting color in sync with mid-high acoustic frequencies.
- A fluid-dynamic quantum nebula background composed of multi-layered, twisting simplex noise that simulates dense aquatic aether.
- Ethereal subsurface scattering through the axolotl's crystalline body, refracting internal light and ambient nebula plasma.
- Interactive gravity manipulation, allowing the user's cursor to draw glowing ripple currents in the surrounding nebula that push and pull the creature's tail and gills.

## Technical Implementation
- File: public/shaders/gen-luminescent-aether-plasma-astro-axolotl.wgsl
- Category: generative
- Tags: ["axolotl", "plasma", "aether", "organic", "volumetric", "fractal", "aquatic", "audio-reactive"]
- Algorithm: Raymarching combined with recursive fractal displacement for the gills, fluid-dynamic noise warping for the environment, and interactive domain distortion.

### Core Algorithm
The shader will construct the axolotl using a composite SDF of stretched spheres, tapered capsules, and curved planes for the tail fin.
- The external gills will utilize a recursive fractal function (similar to 3D L-systems) applied to a base cylinder SDF, with rotation angles driven by a slow time parameter (`u.config.x`) and audio input (`plasmaBuffer[1].x`).
- The fluid nebula will bypass standard raymarching, instead accumulating color along the ray using a 3D simplex noise function that translates slowly along the Z-axis, simulating an infinite drift.

### Mouse Interaction
The mouse (via `u.zoom_config.yz`) generates a local spacetime distortion vector field. This vector field locally offsets the `p` vector during the SDF evaluation, applying a smooth, inverse-square warp that causes the axolotl's tail and gills to dynamically bend and flow toward or away from the cursor as if disturbed by physical water currents.

### Color Mapping / Shading
The palette will contrast deep, oceanic abyssal blues and quantum purples with blistering neon pinks, cyans, and golds for the bioluminescence. The axolotl's body uses a custom refraction/subsurface scattering approximation, picking up ambient light from the nebula. The gills and eyes emit intense light (bloom) directly mapped to `plasmaBuffer[0].x` (bass) and `plasmaBuffer[1].x` (mid-highs).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Luminescent Aether-Plasma Astro-Axolotl
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
    zoom_params: vec4<f32>,  // x=Gill Expansion, y=Current Warp, z=Nebula Density, w=Bioluminescence
    ripples: array<vec4<f32>, 50>,
};

// ... (Utility functions: rot2D, noise, smooth_min)

fn map(p: vec3<f32>) -> vec2<f32> {
    var p_warp = p;
    // Mouse current warp
    let mouse = u.zoom_config.yz;
    let dist = length(p_warp.xy - vec2<f32>(mouse.x * 2.0, mouse.y * 2.0));
    let warp_factor = u.zoom_params.y / (1.0 + dist * dist * 5.0);
    p_warp -= vec3<f32>(mouse.x, mouse.y, 0.0) * warp_factor;

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

Gill Expansion (1.0, 0.1, 3.0, 0.05)
Current Warp (0.6, 0.0, 2.0, 0.05)
Nebula Density (0.5, 0.0, 1.0, 0.01)
Bioluminescence (1.2, 0.0, 3.0, 0.1)
