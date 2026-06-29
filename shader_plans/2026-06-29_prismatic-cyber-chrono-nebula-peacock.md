# New Shader Plan: Prismatic Cyber-Chrono Nebula-Peacock

## Overview
A hyper-majestic, biomechanical celestial peacock woven from shattered quantum glass and glowing liquid-aurora, endlessly expanding its fractal plumage of volumetric time-feathers across a deep-space nebula while reacting explosively to ambient acoustic frequencies.

## Features
- **Fractal Chrono-Plumage:** Procedurally generated fractal tail feathers that expand and fold through geometric domain repetition, mirroring the intricate structure of a peacock's train.
- **Audio-Reactive Eye-Spots:** Intense, violently pulsating quantum 'eye-spots' on each feather that dilate and glow with liquid aurora during deep acoustic bass drops.
- **Volumetric Quantum-Glass Body:** The peacock's core body is forged from refractive, multi-layered quantum glass, dispersing light and fracturing space around it.
- **Nebular Plasma-Storm:** The entity floats within a chaotic, dense volumetric plasma-ocean of swirling aether-particles, providing a deep cosmic backdrop.
- **Chrono-Distortion Ripples:** Moving the mouse creates intense gravitational ripples that warp the fractal plumage and bend the surrounding nebula's light.
- **Liquid-Aurora Luminescence:** Fluid, shifting gradients of iridescent teal, magenta, and gold light up the cybernetic skeletal structure.

## Technical Implementation
- File: public/shaders/gen-prismatic-cyber-chrono-nebula-peacock.wgsl
- Category: generative
- Tags: ["organic", "quantum", "cosmic", "mechanical", "peacock", "audio-reactive", "fractal"]
- Algorithm: Raymarching with heavily layered SDFs, geometric folding, volumetric absorption/scattering, and audio-driven domain warping.

### Core Algorithm
The entity is constructed using raymarching. The main body combines sleek tubular SDFs with crystalline subtraction shapes to form the cyber-glass body. The tail (plumage) utilizes polar domain repetition combined with iterative fractal folding (similar to KIFS or Mandelbox folds) to generate the intricate, overlapping feathers. The 'eyes' of the feathers are spheres embedded within the folded space, specifically triggered to glow intensely based on `u.config.y` (audio). Background is a volumetric raymarch through multi-octave 3D Simplex noise to create the plasma nebula.

### Mouse Interaction
The mouse (`u.mouse`) acts as a gravitational singularity. When positioned near the center, it smoothly rotates the entire entity, providing an orbital camera feel. Additionally, the distance from the mouse to the center of the screen drives a spherical warping function that curves the outer fractal feathers, creating a 'display' effect where the peacock spreads its plumage based on mouse interaction.

### Color Mapping / Shading
The body uses a high-IOR (Index of Refraction) glass shader approach, calculating internal reflections and chromatic aberration. The feathers utilize a metallic shading model overlaid with an emissive iridescent map based on domain coordinates, creating the liquid-aurora effect. Bloom is heavily applied to the audio-reactive 'eyes' and the surrounding nebular plasma.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Prismatic Cyber-Chrono Nebula-Peacock
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
    resolution: vec2<f32>,
    mouse: vec2<f32>,
    config: vec4<f32>, // x: time, y: audio, z/w: unused
    zoom_params: vec4<f32>, // custom UI slider parameters
    camera_pos: vec3<f32>,
    camera_dir: vec3<f32>,
}

// ----------------------------------------------------------------
// HELPER FUNCTIONS
// ----------------------------------------------------------------
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ----------------------------------------------------------------
// SDF & DOMAIN FUNCTIONS
// ----------------------------------------------------------------
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdCylinder(p: vec3<f32>, h: vec2<f32>) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - h;
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

fn map(pos: vec3<f32>) -> vec2<f32> {
    var p = pos;
    let time = u.config.x;
    let audio = u.config.y;

    // Core structure logic goes here...
    // 1. Mouse rotation & distortion
    // 2. Peacock cyber-body SDF
    // 3. Fractal plumage via folding

    var d = sdSphere(p, 1.0); // Placeholder
    return vec2<f32>(d, 1.0); // .x = distance, .y = material id
}

// ----------------------------------------------------------------
// SHADING & RAYMARCHING
// ----------------------------------------------------------------
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(
        e.xyy * map(p + e.xyy).x +
        e.yyx * map(p + e.yyx).x +
        e.yxy * map(p + e.yxy).x +
        e.xxx * map(p + e.xxx).x
    );
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }

    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    let uv = (fragCoord * 2.0 - u.resolution.xy) / u.resolution.y;

    // Ray setup
    let ro = u.camera_pos;
    let rd = normalize(vec3<f32>(uv, 1.5));

    // Raymarching loop...

    let finalColor = vec4<f32>(uv.x, uv.y, 0.5, 1.0); // Placeholder

    textureStore(writeTexture, vec2<i32>(id.xy), finalColor);
}
```

## Parameters (for UI sliders)

- Plumage Spread (`zoom_params.x`): default 0.5, min 0.0, max 1.0, step 0.01
- Quantum Glass Refraction (`zoom_params.y`): default 1.2, min 1.0, max 2.5, step 0.01
- Nebula Density (`zoom_params.z`): default 0.8, min 0.1, max 2.0, step 0.05
- Audio Reactivity (`zoom_params.w`): default 1.0, min 0.0, max 3.0, step 0.05

## Integration Steps

1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
