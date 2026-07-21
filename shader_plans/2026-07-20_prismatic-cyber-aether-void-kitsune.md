# New Shader Plan: Prismatic Cyber-Aether Void-Kitsune

## Overview
A hyper-majestic, cybernetic celestial kitsune forged from shattered prismatic glass and liquid quantum-aether, bounding violently through a multi-dimensional volumetric particle-storm while its nine radiant tails carve temporal auroral rifts into the void.

## Features
- **Dynamic Organic-Mechanical Kitsune Geometry:** Intricately modeled through advanced raymarching and smooth-min operations, featuring a sleek cybernetic body and nine distinct flowing tails.
- **Nine Volumetric Aether Tails:** The tails use domain-repetition and recursive fractal displacement, pulsating with chaotic aether-plasma that violently reacts to heavy sub-bass drops.
- **Quantum-Storm Void Environment:** A deeply volumetric background composed of multi-layered, translating 3D simplex noise simulating an infinite, collapsing dark-matter particle storm.
- **Prismatic Subsurface Refraction:** The kitsune's crystalline armor refracts ambient nebula light, dispersing intense prismatic hues (blazing oranges, neon magentas, and quantum teals).
- **Audio-Reactive Bioluminescent Runes:** Geometric cyber-runes etched along the kitsune's body emit liquid bioluminescence directly synchronized with mid-high acoustic frequencies.
- **Interactive Spacetime Distortion:** Gravity manipulation via cursor interaction, generating glowing ripple currents in the aether that bend and distort the kitsune's tails and the surrounding particle-storm.

## Technical Implementation
- File: public/shaders/gen-prismatic-cyber-aether-void-kitsune.wgsl
- Category: generative
- Tags: ["kitsune", "cybernetic", "prismatic", "aether", "volumetric", "fractal", "audio-reactive"]
- Algorithm: Raymarching combined with recursive fractal displacement for the nine tails, fluid-dynamic noise warping for the environment, and interactive domain distortion.

### Core Algorithm
The shader constructs the cybernetic kitsune using a composite SDF of tapered capsules, elongated spheres, and hard-edge chamfered boxes for the mechanical armor.
- The nine tails are modeled using polar domain repetition wrapped around the rear, utilizing a recursive fractal function (like a 3D L-system or smooth-min layered noise) applied to base cylinder SDFs. Their animation is driven by a slow time parameter (`u.config.x`) and audio input (`plasmaBuffer[0].x`).
- The particle-storm void bypasses traditional raymarching, accumulating density and color along the ray using a 3D simplex noise function that translates slowly along the Z-axis.

### Mouse Interaction
The mouse (via `u.zoom_config.yz`) generates a local spacetime distortion vector field. This vector field locally offsets the `p` vector during the SDF evaluation (e.g., `let mouse = u.zoom_config.yz; let p_warp = p - vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0);`), applying a smooth, inverse-square warp that causes the kitsune's tails and surrounding aether to dynamically bend and flow toward or away from the cursor.

### Color Mapping / Shading
The palette contrasts deep, abyssal dark-matter purples and void-blacks with intense, blistering neon oranges, magentas, and cyans for the bioluminescence. The kitsune's cybernetic armor uses a custom refraction/subsurface scattering approximation, picking up ambient light from the particle storm. The tails and runes emit intense light (bloom) directly mapped to `plasmaBuffer[0].x` (bass) and `plasmaBuffer[1].x` (mid-highs).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Prismatic Cyber-Aether Void-Kitsune
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
    zoom_params: vec4<f32>,  // x=Tail Dispersion, y=Current Warp, z=Storm Density, w=Rune Glow
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

Tail Dispersion (1.0, 0.1, 3.0, 0.05)
Current Warp (0.6, 0.0, 2.0, 0.05)
Storm Density (0.5, 0.0, 1.0, 0.01)
Rune Glow (1.2, 0.0, 3.0, 0.1)
