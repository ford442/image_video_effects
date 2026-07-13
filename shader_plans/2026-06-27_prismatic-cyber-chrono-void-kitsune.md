# New Shader Plan: Prismatic Cyber-Chrono Void-Kitsune

## Overview
A hyper-majestic, nine-tailed cybernetic space-fox woven from shattering prismatic quantum glass and glowing liquid-aurora, effortlessly bounding through an endlessly twisting volumetric cosmic-rift while its fluid tails carve geometric chrono-fractals into the void.

## Features
- Nine Morphing Quantum Tails: The kitsune's tails are procedural bundles of liquid-neon fiber optics that independently ripple, split, and re-merge using multi-domain fractal noise.
- Crystalline Cyber-Flesh Exoskeleton: Hard-edged, semi-transparent biomechanical armor plating forged from prismatic glass, reflecting a twisted volumetric nebula background.
- Sonic-Reactive Chrono-Runes: Intricate geometric patterns etched into the exoskeleton that aggressively pulse and shift from deep ultraviolet to blinding gold on heavy bass drops.
- Volumetric Aether-Rift: The entity navigates through an endlessly scrolling, heavily distorted tubular SDF environment resembling a tearing cosmic wormhole.
- Gravitational Plasma Dust: Brilliant motes of scattered quantum energy that are gravitationally sucked into the vortex created by the kitsune's nine sweeping tails.

## Technical Implementation
- File: public/shaders/gen-prismatic-cyber-chrono-void-kitsune.wgsl
- Category: generative
- Tags: ["cosmic", "kitsune", "quantum", "crystal", "organic", "mechanical", "audio-reactive", "volumetric"]
- Algorithm: Raymarching combining smooth-min organic shapes for the body, L-system-inspired multi-spline paths for the tails, and a tubular volumetric density accumulator for the rift.

### Core Algorithm
- The central body uses an advanced combination of ellipsoid, capsule, and box SDFs smoothed together with `smin` and perturbed by high-frequency 3D cellular noise for biomechanical detailing.
- The nine tails are evaluated by twisting and domain-warping a cylindrical SDF along a series of overlapping sine waves, driven by the shader's time uniform for fluid, independent motion.
- The volumetric background rift is generated using a hollow cylinder SDF mapped with multi-octave gyroid noise, raymarched with density accumulation to simulate thick glowing gas.
- The gravity dust is created by instancing volumetric points scattered via a 3D hash function, whose trajectories are warped toward the moving tails.

### Mouse Interaction
- Moving the mouse steers the kitsune's bounding trajectory, applying a localized spatial bend (using smoothstep and rotation matrices) that slightly distorts the entire SDF scene.
- Clicking sends a shockwave through the aether-rift, causing the nine tails to flare outward defensively while releasing a sudden burst of brilliant plasma dust.

### Color Mapping / Shading
- The cyber-glass armor utilizes faux-refraction by sampling the background noise field heavily distorted by the surface normal, paired with iridescent chromatic aberration.
- The chrono-runes and plasma dust are purely emissive, blooming intensely and mapped to `u.zoom_params` (audio input) for highly reactive neon coloration (magenta/cyan/gold).
- The volumetric rift uses a complex Blackbody-inspired color ramp, shifting from deep violet absorption in the dense regions to bright plasma pinks along the edges.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Prismatic Cyber-Chrono Void-Kitsune
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Tail Dispersion, y=Rift Density, z=Rune Intensity, w=Glass Refraction
    ripples: array<vec4<f32>, 50>,
};

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

// ----------------------------------------------------------------
// Helper functions and Math utilities
// ----------------------------------------------------------------
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// ----------------------------------------------------------------
// Main Compute
// ----------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dim = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<f32>(f32(id.x), f32(id.y));

    if (coord.x >= dim.x || coord.y >= dim.y) {
        return;
    }

    let uv = (coord - 0.5 * dim) / dim.y;

    // ... Raymarching and shading implementation ...

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(uv.x, uv.y, 0.5, 1.0));
}
```

Parameters (for UI sliders)

Tail Dispersion (1.0, 0.1, 3.0, 0.1)
Rift Density (0.8, 0.1, 2.0, 0.05)
Rune Intensity (1.5, 0.5, 5.0, 0.1)
Glass Refraction (0.7, 0.0, 1.0, 0.05)

Integration Steps

1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
