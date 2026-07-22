# New Shader Plan: Luminescent Quantum-Flora Symphony

## Overview
A hyper-dimensional, symbiotic cyber-botanical ecosystem forged from fractal quantum-glass and liquid starlight, blooming endlessly in a zero-gravity dark matter void while its neon-infused petals violently ripple to acoustic sub-bass frequencies.

## Features
- **Fractal Botanical Geometry:** Complex 3D fractal smooth-min SDFs that generate blooming, recursive petal structures that evolve over time.
- **Symbiotic Glass Petals:** A hyper-refractive quantum-glass material that scatters deeply saturated prismatic light through multiple sub-surface layers.
- **Audio-Reactive Nectar Core:** A violently glowing, liquid starlight core that pulses intensely in size and brightness, driven by sub-bass and mid frequencies.
- **Zero-Gravity Spores:** Thousands of tiny, glowing geometric spores drifting through a volumetric dark-matter field, creating dynamic parallax.
- **Ethereal Chromatic Aberration:** Deep, saturated color mapping (neon magenta, electric cyan, and solar gold) that shifts dynamically as the flora rotates and unfolds.
- **Tension-String Gravity Fields:** Mouse interaction plucks unseen cosmic strings, creating localized gravitational waves that warp and twist the surrounding petals and spores.

## Technical Implementation
- File: public/shaders/gen-luminescent-quantum-flora-symphony.wgsl
- Category: generative
- Tags: ["flora", "botanical", "quantum", "fractal", "audio-reactive", "cosmic", "luminescent"]
- Algorithm: Advanced volumetric raymarching combining recursive folding space (KIFS) for the flora geometry with deep sub-surface scattering and flow-noise for the dark-matter void.

### Core Algorithm
The cyber-flora is constructed using a Kaleidoscopic Iterated Function System (KIFS) combined with spherical folding and smooth-minimum operators to create sharp yet organic petal-like structures.
- The generative geometry evolves over time by interpolating the folding angles driven by `u.config.x` (Time).
- The zero-gravity spores are generated using domain repetition over a 3D grid with random offsets derived from high-frequency hash functions.
- A volumetric pass creates the dark-matter void using 3D fractional Brownian motion (fBm) noise to simulate viscous cosmic dust.

### Mouse Interaction
The cursor (via `u.zoom_config.yz`) acts as a localized gravity disruption field. The distance from the ray origin to the mouse position is calculated, and an inverse-square attenuation function is used to apply a rotational twist to the coordinate space `p`. This effectively "plucks" the flora, causing the fractal petals to violently twist towards or away from the cursor depending on a tension parameter.

### Color Mapping / Shading
The palette contrasts deep void blacks with blinding, hyper-saturated neon magenta, electric cyan, and solar gold. The shading model utilizes deep sub-surface scattering to give the quantum-glass petals a milky, translucent quality. The intensity of the central nectar core and the emission strength of the scattered spores are directly modulated by `plasmaBuffer[0].x` (bass) and `plasmaBuffer[1].x` (mids), creating explosive bursts of light synced to the audio.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Luminescent Quantum-Flora Symphony
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
    zoom_params: vec4<f32>,  // x=Petal Complexity, y=Gravity Twist, z=Spore Density, w=Core Intensity
    ripples: array<vec4<f32>, 50>,
};

// ... (Utility functions: rot2D, hash33, fBm, smin)

fn map(p: vec3<f32>) -> vec2<f32> {
    var p_warp = p;
    // Mouse tension-string interaction
    let mouse = u.zoom_config.yz;
    let delta = p_warp.xy - vec2<f32>(mouse.x * 2.0, mouse.y * 2.0);
    let dist = length(delta);
    let twist_factor = u.zoom_params.y / (1.0 + dist * dist * 4.0);

    // Apply localized twist
    let angle = twist_factor * 3.14159;
    let s = sin(angle);
    let c = cos(angle);
    p_warp.x = delta.x * c - delta.y * s + mouse.x * 2.0;
    p_warp.y = delta.x * s + delta.y * c + mouse.y * 2.0;

    // KIFS Fractal generation driven by u.zoom_params.x...

    return vec2<f32>(1.0, 0.0);
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    // Standard raymarching loop with volumetric accumulation
    return vec2<f32>(0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }
    let uv = vec2<f32>(f32(id.x) / f32(dimensions.x), f32(id.y) / f32(dimensions.y));

    // Core pixel calculation and shading logic...
    textureStore(writeTexture, vec2<i32>(i32(id.x), i32(id.y)), vec4<f32>(uv, 0.0, 1.0));
}
```

Parameters (for UI sliders)

Petal Complexity (1.0, 0.1, 5.0, 0.1)
Gravity Twist (0.5, 0.0, 2.0, 0.05)
Spore Density (0.8, 0.0, 2.0, 0.05)
Core Intensity (1.5, 0.1, 4.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
