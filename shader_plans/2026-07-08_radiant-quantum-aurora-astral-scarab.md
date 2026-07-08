# New Shader Plan: Radiant Quantum-Aurora Astral-Scarab

## Overview
A hyper-majestic, cybernetic astral-scarab woven from flowing quantum plasma and shattered aether-glass, crawling through an endlessly shifting dark-matter void while projecting a monolithic auroral hologram from its iridescent carapace, intensely reacting to cascading acoustic frequencies.

## Features
- **Monolithic Auroral Hologram:** The scarab's carapace acts as a prism, projecting an ever-shifting, volumetric auroral hologram that responds to acoustic peaks.
- **Biomechanical Kinetic Limbs:** The scarab's legs utilize intricate IK (inverse kinematics) through stacked sine waves, creating fluid, unsettlingly organic movement across invisible quantum terrain.
- **Quantum Plasma Core:** A blazing, multi-layered energy core visible through the fractured aether-glass of its abdomen, emitting heavy subsurface scattering and bloom.
- **Fractal Void Particles:** The surrounding environment is filled with swirling fractal dust that is gravitationally pulled toward the scarab's core and expelled upon heavy bass drops.
- **Temporal Displacement:** The scarab leaves behind transient glowing afterimages of itself that slowly fade, creating a trail of temporal echoes.
- **Gravitational Mouse Interaction:** The mouse cursor acts as an immense gravity well, dragging the scarab out of its path and twisting its projected holograms toward the viewer.

## Technical Implementation
- File: public/shaders/gen-radiant-quantum-aurora-astral-scarab.wgsl
- Category: generative
- Tags: ["scarab", "quantum", "aurora", "biomechanical", "audio-reactive", "holographic", "void"]
- Algorithm: Raymarching complex interlocking SDFs for the biomechanical body, combined with volumetric accumulation for the hologram and plasma core.

### Core Algorithm
- **Interlocking SDFs:** Construct the scarab using intersecting ellipsoids, capsules, and boxes with smooth min/max operations, mapped onto domain-warped coordinates for the fractured aesthetic.
- **Kinematic Limb Movement:** Drive the positions and rotations of the leg segments using phase-shifted sine waves linked to the global time uniform (`u.config.x`), combined with audio input (`u.config.y`) to induce rapid spasms on beat drops.
- **Volumetric Hologram:** Use raymarching accumulation through a 3D fractional Brownian motion (fBm) noise field, centered above the carapace, with density modulating based on view angle and acoustic intensity.
- **Temporal Echoes:** Utilize the `readTexture` (previous frame) mixed with the current frame's output to create persistent, fading afterimages.

### Mouse Interaction
- The mouse coordinates `u_pointer` drive a gravitational anchor point.
- The scarab's forward momentum is perturbed, smoothly interpolating its orientation to face the anchor point.
- The volumetric hologram bends and distorts as if affected by gravitational lensing toward the mouse position.

### Color Mapping / Shading
- **Iridescent Carapace:** Apply a physically based rendering (PBR) inspired material model using an iridescent color palette (gold -> teal -> magenta) based on the Fresnel effect and surface normals.
- **Subsurface Glow:** Inject a high-intensity hot-pink to cyan gradient into the core using depth-based attenuation within the SDF volume.
- **Holographic Bleed:** Apply strong emissive colors to the volumetric accumulation, allowing natural light bleed and bloom to wash over the scarab's body.

## Proposed Code Structure (WGSL)
```wgsl
struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// ----------------------------------------------------------------
// Radiant Quantum-Aurora Astral-Scarab
// Category: generative
// ----------------------------------------------------------------

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

// Constants & Utilities
const PI: f32 = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// SDF primitives and combinations...

// Volumetric noise for hologram...

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }

    let uv = vec2<f32>(global_id.xy) / vec2<f32>(dims);

    let time = u.config.x;
    let audio = u.config.y;
    let mouse = u.zoom_config.yz;

    // Raymarching setup, evaluation, and coloring logic here...

    textureStore(writeTexture, global_id.xy, vec4<f32>(uv.x, uv.y, sin(time), 1.0));
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Core Intensity (1.2, 0.0, 5.0, 0.1)
- Crawl Speed (1.0, 0.1, 3.0, 0.1)
- Hologram Density (1.5, 0.5, 4.0, 0.1)
- Temporal Echo Decay (0.9, 0.5, 0.99, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager