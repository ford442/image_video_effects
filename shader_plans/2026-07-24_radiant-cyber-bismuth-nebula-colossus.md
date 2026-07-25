# New Shader Plan: Radiant Cyber-Bismuth Nebula-Colossus

## Overview
A colossal, hyper-dimensional biomechanical titan woven from shattered cyber-bismuth lattices and liquid auroral plasma, drifting endlessly through a violently decaying quantum-particle storm.

## Features
- Intricate, endlessly evolving fractal bismuth geometries forming the titan's core superstructure
- Volumetric quantum-particle storms swirling organically around its massive frame
- Subsurface scattering through liquid auroral plasma, reacting dynamically to audio sub-bass
- Liquid chrome and glowing cybernetic tendrils linking floating spatial shards
- Intense dynamic bioluminescence emitting deep spatial glows
- Time-warping gravitational lensing effects centered at the colossus core
- Smooth, high-frequency spatial noise creating micro-details on metallic surfaces

## Technical Implementation
- File: public/shaders/gen-radiant-cyber-bismuth-nebula-colossus.wgsl
- Category: generative
- Tags: ["cosmic", "bismuth", "fractal", "bioluminescence", "audio-reactive", "quantum", "colossus"]
- Algorithm: A multi-pass raymarching system combining hyper-complex IFS (Iterated Function Systems) for bismuth structures, layered 3D value noise for volumetric nebulae, and SDF-based soft shadows and ambient occlusion.

### Core Algorithm
The primary raymarcher will evaluate an SDF field where the base shape is a combination of massive octahedrons modified by intense recursive folding (IFS). These folds will use varying rotational offsets to generate the stepped, labyrinthine structures characteristic of bismuth crystals. Volumetric raymarching is blended in to sample dense 3D noise (Simplex/Worley) for the surrounding nebula, heavily distorted by domain warping.

### Mouse Interaction
Mouse movement (mapped to `u.zoom_config.yz`) shifts the local origin of the fractal folding equations. This causes the colossus to seemingly turn its attention and orient its crystalline facets toward the cursor, while simultaneously acting as a gravity well that bends the surrounding volumetric particle storm toward the mouse position based on inverse-square distance.

### Color Mapping / Shading
A vivid, iridescent gradient mapped to the SDF normals and orbit traps. Base colors shift through deep magentas, hyper-cyans, and liquid golds. The material shading incorporates a fake subsurface scattering using density accumulation, alongside sharp metallic specular highlights driven by ambient directional lights. The audio input (`plasmaBuffer[0].x`) modulates the emissive glow intensity and chromatic aberration spread.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Radiant Cyber-Bismuth Nebula-Colossus
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var non_filtering_sampler: sampler;
@group(0) @binding(5) var readDepthTexture: texture_depth_2d;
@group(0) @binding(6) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(7) var<storage, read> plasmaBuffer: array<vec4<f32>>;
@group(0) @binding(8) var extraDepthTexture: texture_depth_2d;
@group(0) @binding(9) var extraReadTexture: texture_2d<f32>;
@group(0) @binding(10) var u_sampler_2: sampler;
@group(0) @binding(11) var readTexture_2: texture_2d<f32>;
@group(0) @binding(12) var u_sampler_3: sampler;

struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    frame: u32,
    mouse: vec4<f32>,
    zoom_config: vec4<f32>, // .x = zoom, .yz = offset
    post_fx: vec4<f32>, // .x = bloom threshold, .y = bloom intensity, .z = chromatic aberration
    slider1: f32,
    slider2: f32,
    slider3: f32,
    slider4: f32,
    slider5: f32,
    slider6: f32,
}

// Complex 3D rotation matrix
fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rotZ(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

// Main SDF Mapping
fn map(pos: vec3<f32>) -> f32 {
    var p = pos;
    let mouse = u.zoom_config.yz;
    p = p - vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0);

    // IFS Bismuth Folding
    for (var i = 0; i < 5; i++) {
        p = abs(p) - vec3<f32>(0.5, 0.8, 0.5) * u.slider1;
        p = p * rotX(u.time * 0.1) * rotY(u.time * 0.15);
    }

    let base_dist = length(max(abs(p) - vec3<f32>(1.0), vec3<f32>(0.0))) - 0.2;
    return base_dist;
}

// Compute Normals
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

// Main Compute Shader
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(u.resolution);
    if (coords.x >= res.x || coords.y >= res.y) { return; }

    let uv = (vec2<f32>(coords) - u.resolution * 0.5) / u.resolution.y;

    let ro = vec3<f32>(0.0, 0.0, -5.0 + u.slider6 * 2.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var max_d = 10.0;
    var d = 0.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        d = map(p);
        if (d < 0.001 || t > max_d) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    if (t < max_d) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let light = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light), 0.0);

        let audio_react = plasmaBuffer[0].x * u.slider3;

        // Iridescent coloring
        col = vec3<f32>(0.5) + 0.5 * cos(u.time + p.xyx * 2.0 + vec3<f32>(0.0, 2.0, 4.0));
        col *= diff;
        col += vec3<f32>(1.0, 0.2, 0.8) * audio_react * 2.0; // Emissive glow
    } else {
        // Volumetric background
        col = vec3<f32>(0.05, 0.02, 0.1) * (1.0 - length(uv));
    }

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)

Fractal Fold Scale (1.0, 0.1, 3.0, 0.01)
Nebula Density (0.5, 0.0, 1.0, 0.01)
Audio Reactivity (1.0, 0.0, 5.0, 0.1)
Iridiscent Shift (0.5, 0.0, 1.0, 0.01)
Metallic Roughness (0.2, 0.0, 1.0, 0.01)
Camera Distance (0.5, 0.0, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
