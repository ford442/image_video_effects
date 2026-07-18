# New Shader Plan: Radiant Quantum-Chrono Star-Wolf

## Overview
A hyper-majestic, cybernetic space-wolf woven from raw quantum energy and shattered temporal chrono-glass, howling silently into a dense, volumetric nebula while its bioluminescent mane ripples with audio-reactive plasma shockwaves.

## Features
- Ethereal Chrono-Glass Anatomy: The wolf's body is built from sharply faceted, semi-transparent fractal polygons that heavily refract the surrounding nebula.
- Flowing Quantum-Plasma Mane: A swirling, volumetric fluid simulation wrapping the neck and back, composed of twisting ribbons of liquid neon that violently flare on bass drops.
- Piercing Temporal Gaze: Blinding, high-intensity glowing eyes that leave short-lived chromatic trails as the wolf’s head tracks through the scene.
- Volumetric Stardust Void: A deep, swirling background of turbulent noise and raymarched volumetric density, imitating a highly energized stellar nursery.
- Sonic Howl Shockwaves: Radial distortions that ripple outwards from the wolf's maw, severely warping the space-time of the background void based on the audio uniform.

## Technical Implementation
- File: public/shaders/gen-radiant-quantum-chrono-star-wolf.wgsl
- Category: generative
- Tags: ["cosmic", "wolf", "quantum", "crystal", "organic", "mechanical", "audio-reactive", "volumetric"]
- Algorithm: Raymarching combining smooth-min organic shapes for the internal core with L-system-inspired multi-spline paths and hard-edged domain repetitions for the chrono-glass armor, nested inside a volumetric density integrator for the nebula.

### Core Algorithm
- The wolf's core uses an advanced combination of ellipsoid, capsule, and box SDFs smoothed together with `smin`.
- The chrono-glass armor is evaluated by twisting and domain-warping a series of geometric primitives over the core surface.
- The quantum-plasma mane utilizes heavily layered 3D curl noise applied to a volumetric cylinder SDF, creating fluid-like ribbons that accumulate density along the ray path.
- The sonic howl shockwaves apply a localized spatial bend (using distance from the maw) that distorts the uv and ray marching domain.

### Mouse Interaction
- Moving the mouse smoothly orbits the camera around the wolf while the head tracks the cursor, giving a powerful sense of scale and presence.
- Clicking triggers a sudden contraction and expansion of the plasma mane, releasing a burst of highly energetic stardust particles into the void.

### Color Mapping / Shading
- The chrono-glass armor utilizes faux-refraction by sampling the background noise field heavily distorted by the surface normal, paired with iridescent chromatic aberration.
- The plasma mane and eyes are purely emissive, blooming intensely and mapped to `u.zoom_params` (audio input) for highly reactive neon coloration (electric blue/violet/gold).
- The volumetric nebula uses a complex Blackbody-inspired color ramp, shifting from deep indigo absorption in the dense regions to bright plasma pinks along the edges.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Radiant Quantum-Chrono Star-Wolf
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Mane Intensity, y=Nebula Density, z=Glass Refraction, w=Howl Distortion
    ripples: array<vec4<f32>, 50>,
};

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

// ----------------------------------------------------------------
// Helper functions and Math utilities
// ----------------------------------------------------------------
const PI = 3.14159265359;

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

Mane Intensity (1.5, 0.1, 5.0, 0.1)
Nebula Density (0.8, 0.1, 2.0, 0.05)
Glass Refraction (0.7, 0.0, 1.0, 0.05)
Howl Distortion (1.0, 0.0, 3.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-06-30_radiant-quantum-chrono-star-wolf.md" "Radiant Quantum-Chrono Star-Wolf"
Reply with only: "✅ Plan created and queued: 2026-06-30_radiant-quantum-chrono-star-wolf.md"