# New Shader Plan: Abyssal Cyber-Aether Void-Kraken

## Overview
A colossal, biomechanical deep-void kraken constructed from shifting abyssal plasma and razor-sharp obsidian geometry, dragging itself through a dense, fluid-dynamic dark-matter nebula while its massive tentacles emit violent audio-reactive bioluminescent pulses.

## Features
- **Massive Biomechanical Kraken:** Constructed using complex smooth-min SDFs combining rigid mechanical carapaces with fluid, undulating tentacles.
- **Procedural Tentacle Kinetics:** Dozens of twisting tentacles modeled with 3D recursive displacement and polar repetition, wrapping chaotically through the void.
- **Deep-Void Fluid Nebula:** A heavy, viscous volumetric background composed of multi-layered flow-noise, mimicking the crush of a deep-sea quantum abyss.
- **Acoustic Shockwave Pulses:** Blinding bioluminescent pulses (neon cyan and radioactive green) that travel down the length of the tentacles, synchronized perfectly with sub-bass frequencies.
- **Obsidian Subsurface Scattering:** The mechanical segments feature an abyssal dark-glass material that heavily refracts the surrounding bioluminescence and nebula light.
- **Vortex Gravity Interaction:** Cursor interaction creates an immense gravitational maelstrom, violently pulling the tentacles and background nebula particles toward the cursor point with a twisting vortex math.

## Technical Implementation
- File: public/shaders/gen-abyssal-cyber-aether-void-kraken.wgsl
- Category: generative
- Tags: ["kraken", "cybernetic", "abyssal", "aether", "volumetric", "fractal", "audio-reactive", "tentacles"]
- Algorithm: Advanced raymarching with complex domain repetition and twisting for the tentacles, volumetric flow-noise for the abyss, and a gravitational vortex warp.

### Core Algorithm
The cyber-kraken's central mantle is formed from interlocking chamfered boxes and spheres combined with smooth-min functions to create a seamless organic-mechanical look.
- The tentacles utilize polar domain repetition along a central axis, heavily distorted using a combination of sine-wave twisting and recursive noise functions to simulate fluid, independent motion.
- The deep-void nebula relies on a volumetric ray-marching pass that accumulates heavy, viscous flow-noise density, bypassing standard surface normals for a purely atmospheric effect.

### Mouse Interaction
The cursor (via `u.zoom_config.yz`) generates a powerful vortex gravity well. The coordinate space `p` is rotated and pulled towards the mouse position using a smooth inverse-square attenuation. The rotation angle is proportional to the inverse distance from the mouse, creating a twisting maelstrom effect that physically bends the tentacles and the volumetric fluid.

### Color Mapping / Shading
The palette is deeply atmospheric, dominated by pitch blacks, deep obsidian greys, and abyssal indigos. This dark canvas is violently pierced by searing bioluminescent neon cyan and radioactive lime green. The bioluminescence intensity and spread are driven directly by `plasmaBuffer[0].x` (bass) and `plasmaBuffer[1].x` (mid-highs), creating explosive shockwaves of light.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Abyssal Cyber-Aether Void-Kraken
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
    zoom_params: vec4<f32>,  // x=Tentacle Thrash, y=Vortex Strength, z=Abyss Density, w=Bioluminescence
    ripples: array<vec4<f32>, 50>,
};

// ... (Utility functions: rot2D, noise, smooth_min)

fn map(p: vec3<f32>) -> vec2<f32> {
    var p_warp = p;
    // Mouse vortex interaction
    let mouse = u.zoom_config.yz;
    let delta = p_warp.xy - vec2<f32>(mouse.x * 2.0, mouse.y * 2.0);
    let dist = length(delta);
    let vortex_factor = u.zoom_params.y / (1.0 + dist * dist * 3.0);

    // Apply twist
    let angle = vortex_factor * 3.14159;
    let s = sin(angle);
    let c = cos(angle);
    p_warp.x = delta.x * c - delta.y * s + mouse.x * 2.0;
    p_warp.y = delta.x * s + delta.y * c + mouse.y * 2.0;
    p_warp -= vec3<f32>(mouse.x, mouse.y, 0.0) * vortex_factor * 0.5;

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

Tentacle Thrash (1.0, 0.1, 3.0, 0.05)
Vortex Strength (0.8, 0.0, 2.5, 0.05)
Abyss Density (0.7, 0.0, 1.5, 0.01)
Bioluminescence (1.5, 0.0, 4.0, 0.1)
