# New Shader Plan: Acoustic Obsidian Resonator

## Overview
A towering, crystalline obsidian structure that breathes and fractures in perfect synchronization with unseen acoustic frequencies, revealing molten golden cores.

## Features
- Real-time geometric fracture and extrusion based on harmonic resonance.
- Deep, glassy obsidian material with highly reflective facets.
- Internal glowing gold/plasma veins exposed during extreme fracture.
- Mouse-driven acoustic shockwaves that temporarily shatter the structure.
- Smooth volumetric domain repetition creating an endless resonator chamber.
- Complex procedural lighting combining sharp specular highlights and soft internal bloom.
- Chromatic aberration at the fringes of the glass shards.

## Technical Implementation
- File: public/shaders/gen-acoustic-obsidian-resonator.wgsl
- Category: generative
- Tags: ["crystalline", "fracture", "audio-reactive", "obsidian", "gold"]
- Algorithm: Raymarching with domain repetition and audio-reactive geometric displacement.

### Core Algorithm
- **SDFs**: A combination of Box and Octahedron SDFs, intersected and unioned to form complex, faceted crystalline pillars.
- **Displacement**: A high-frequency sine-based displacement layered with voronoi noise, scaled by `plasmaBuffer` audio frequencies (bass for macro displacement, treble for micro fractures).
- **Domain Repetition**: The `q` coordinate is modulo-wrapped (`q = fract(p / spacing) - 0.5 * spacing`) to create an infinite field of resonating pillars.

### Mouse Interaction
- **Behavior**: Clicking creates a localized acoustic gravity well.
- **Formula**: Distance to `u.zoom_config.yz` mapped into world space scales up the fracture intensity exponentially, while `u.zoom_config.w > 0.0` dynamically bends the rays toward the epicenter, acting as a massive spatial distortion.

### Color Mapping / Shading
- **Obsidian**: Base color is near black `vec3(0.01, 0.02, 0.03)` with extremely high specular reflection using a schlick approximation for fresnel.
- **Gold Veins**: When the displacement threshold exceeds a specific limit, the color rapidly transitions to an emissive gold `vec3(1.0, 0.8, 0.2) * 5.0`.
- **Lighting**: Fake volumetric lighting based on ray accumulation, with ambient occlusion derived from the raymarching loop step count (`steps`).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Acoustic Obsidian Resonator
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// --- HELPER FUNCTIONS ---
fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let q = abs(p);
    return (q.x + q.y + q.z - s) * 0.57735027;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// --- SDF MAP ---
fn map(pos: vec3<f32>) -> f32 {
    var p = pos;

    // Mouse distortion
    if (u.zoom_config.w > 0.0) {
        let mouse_uv = u.zoom_config.yz * 2.0 - 1.0;
        let dist = length(p.xy - mouse_uv * 10.0);
        let pull = exp(-dist * 0.5) * u.zoom_params.y;
        p = p + normalize(p) * pull;
    }

    // Domain Repetition
    let spacing = u.zoom_params.w * 5.0;
    p = fract(p / spacing + 0.5) * spacing - 0.5 * spacing;

    // Audio Reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);

    // Rotations
    let rxy = p.xy * rot2D(u.config.x * u.zoom_params.x);
    p = vec3<f32>(rxy, p.z);

    let base_box = sdBox(p, vec3<f32>(1.0, 4.0, 1.0));
    let oct = sdOctahedron(p, 1.5 + bass * u.zoom_params.z);

    // Fracture displacement
    let fracture = sin(p.x * 10.0) * sin(p.y * 10.0) * sin(p.z * 10.0) * mids * 0.2;

    return max(base_box, -oct) + fracture;
}

// --- MAIN COMPUTE ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) { return; }

    let uv = (vec2<f32>(id.xy) * 2.0 - res) / min(res.x, res.y);

    var ro = vec3<f32>(0.0, 0.0, -5.0 + u.config.x);
    var rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var steps = 0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if (d < 0.001 || t > 50.0) { break; }
        t += d;
        steps++;
    }

    var col = vec3<f32>(0.0);
    var depth = 1.0;

    if (t < 50.0) {
        let p = ro + rd * t;
        let ao = 1.0 - f32(steps) / 100.0;

        let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
        let emissive_gold = vec3<f32>(1.0, 0.8, 0.2) * (bass * 2.0);

        col = mix(vec3<f32>(0.02), emissive_gold, smoothstep(0.8, 1.0, ao)) * ao;
        depth = t / 50.0;
    }

    let out_color = vec4<f32>(col, 1.0);
    textureStore(writeTexture, id.xy, out_color);
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(0.0));
}
```

Parameters (for UI sliders)
- Rotation Speed (0.5, 0.0, 2.0, 0.1)
- Shockwave Force (2.0, 0.0, 10.0, 0.5)
- Fracture Scale (1.0, 0.0, 3.0, 0.1)
- Domain Spacing (1.5, 0.5, 5.0, 0.1)

Integration Steps
1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
