# New Shader Plan: Obsidian Echo-Chamber

## Overview
An infinite, abyssal expanse of highly polished, brutalist obsidian monoliths that react to audio by emitting and reflecting brilliant, luminescent echolocation ripples across their glassy surfaces.

## Features
- **Infinite Brutalist Geometry**: Raymarched domain repetition of imposing, jet-black monolithic structures.
- **Perfect Specular Reflections**: Highly polished surfaces that reflect the surrounding void and glowing elements.
- **Audio-Reactive Echolocation**: Pulses of bright, chromatic light (driven by `u.config.y`) that wash over the monoliths like sonar waves.
- **Volumetric Fog**: A dense, dark atmospheric fog that fades structures into the abyss, creating depth and mystery.
- **Dynamic Gravity Shifts**: Monoliths slowly rise, fall, and twist, reconfiguring the labyrinthine space over time.
- **Chromatic Aberration**: Subtle color splitting on the reflections to simulate thick, heavy glass or fractured obsidian.

## Technical Implementation
- File: public/shaders/gen-obsidian-echo-chamber.wgsl
- Category: generative
- Tags: ["brutalist", "obsidian", "audio-reactive", "reflection", "dark"]
- Algorithm: Raymarching with domain repetition, glossy reflections, and distance-based audio-ripple overlays.

### Core Algorithm
- **SDFs**: `sdBox` and `sdCylinder` for monolithic columns and floating slabs.
- **Domain Repetition**: The space is infinitely repeated along the X and Z axes using `opRep` (`p = (p + c/2) % c - c/2`), creating an endless city of monoliths.
- **Raymarching Loop**: Standard sphere-tracing with an increased step count to handle glossy reflections and grazing angles accurately.
- **Reflections**: A secondary raymarching pass calculating the reflection vector `reflect(rd, normal)` to sample the environment and other glowing structures.

### Mouse Interaction
- **View Rotation**: `u.zoom_config.y` and `u.zoom_config.z` control the camera's pitch and yaw, allowing the user to look around the echoing chamber.
- **Sonar Ping on Click**: Clicking (tracked by `u.config.y` spikes or mouse variables) unleashes a massive, high-intensity ripple effect outward from the camera's position.

### Color Mapping / Shading
- **Obsidian Material**: Base color is near pitch-black with a high specular exponent and strong Fresnel effect.
- **Ripple Glow**: The sonar ripples use a vibrant, neon gradient (cyan to magenta) that maps to the fractional part of the distance from the origin minus time, creating moving bands of light.
- **Fog Blending**: `exp(-distance * density)` applied to blend the scene smoothly into a pitch-black background.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Obsidian Echo-Chamber
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Monolith Spacing, y=Ripple Intensity, z=Specular Gloss, w=Forward Speed
    ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

fn rot2D(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn map(p: vec3<f32>) -> f32 {
    var pos = p;
    // Domain repetition
    let spacing = u.zoom_params.x * 5.0 + 5.0; // Slider mapped spacing
    pos.x = (pos.x + spacing * 0.5) % spacing - spacing * 0.5;
    pos.z = (pos.z + spacing * 0.5) % spacing - spacing * 0.5;

    // Vertical shift based on position
    pos.y += sin(p.x * 0.1 + u.config.x) * 2.0;

    // Monolith SDF
    let box = sdBox(pos, vec3<f32>(1.0, 10.0, 1.0));
    return box;
}

// ... Additional helper functions (GetNormal, RayMarch) ...

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    var uv = (fragCoord - 0.5 * res) / res.y;

    // Camera setup with mouse interaction
    var ro = vec3<f32>(0.0, 2.0, -u.config.x * u.zoom_params.w * 5.0); // Moving forward
    var rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    // Mouse rotation
    let mouseX = (u.zoom_config.y / res.x) * 6.2831 - 3.1415;
    let mouseY = (u.zoom_config.z / res.y) * 3.1415 - 1.5707;

    let rotY = rot2D(-mouseX);
    let rotX = rot2D(mouseY);

    // Apply rotations
    let rdYZ = rotX * vec2<f32>(rd.y, rd.z);
    rd.y = rdYZ.x; rd.z = rdYZ.y;

    let rdXZ = rotY * vec2<f32>(rd.x, rd.z);
    rd.x = rdXZ.x; rd.z = rdXZ.y;

    // Raymarching
    let d = map(ro); // Simplified for skeleton

    // Output
    let color = vec4<f32>(vec3<f32>(0.0), 1.0);
    textureStore(writeTexture, vec2<i32>(id.xy), color);
}
```

## Parameters (for UI sliders)

Name (default, min, max, step)
- `u.zoom_params.x`: Monolith Spacing (0.5, 0.1, 1.0, 0.01)
- `u.zoom_params.y`: Audio Ripple Intensity (0.8, 0.0, 1.0, 0.01)
- `u.zoom_params.z`: Specular Glossiness (0.9, 0.0, 1.0, 0.01)
- `u.zoom_params.w`: Forward Speed (0.5, 0.0, 2.0, 0.01)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
