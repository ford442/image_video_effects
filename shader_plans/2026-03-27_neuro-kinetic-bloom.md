# New Shader Plan: Neuro-Kinetic Bloom

## Overview
A vast, deep-sea garden of biomechanical, neon-veined flora that dynamically uncoils and pulses with quantum energy, its tendrils whipping and synchronizing to the rhythm of sound.

## Features
- **Biomechanical Flora:** Intricate, tube-like organic structures generated via raymarching and complex parametric curves.
- **Audio-Reactive Uncoiling:** Tendrils and petals dynamically unroll and extend outwards, driven directly by audio beat accumulation (`u.config.y`).
- **Neon Vein Network:** Glowing, volumetric energy pathways run along the surface of the flora, pulsing brightly on the beat.
- **Subsurface Scattering Approximation:** The organic matter features a soft, translucent look, scattering internal light to create a fleshy, alien appearance.
- **Magnetic Mouse Repulsion:** The mouse cursor acts as a bio-magnetic repulsor, causing the dense flora to part and shy away from the interaction point.
- **Deep-Sea Particulate:** Floating, glowing specks (spores/plankton) drift through the volumetric fog, illuminating the dark void.

## Technical Implementation
- File: public/shaders/gen-neuro-kinetic-bloom.wgsl
- Category: generative
- Tags: ["organic", "biomechanical", "audio-reactive", "flora", "raymarching", "volumetric"]
- Algorithm: Raymarching with heavily domain-warped `sdCapsule` and `sdTorus` primitives, using FBM noise to create organic texturing and audio-driven twisting along the Z-axis.

### Core Algorithm
The geometry relies on creating multiple overlapping, twisted tube-like structures using domain repetition in polar coordinates. The core shape is achieved by twisting space (applying a rotation matrix dependent on the Y or Z axis) before evaluating an `sdCapsule`. The degree of this twist and the length of the capsules are heavily modulated by `u.time` and the audio accumulator `u.config.y`, causing the structures to "bloom" or uncoil.

### Mouse Interaction
A smooth gravitational repulsion field is calculated based on the distance from the world-space coordinate to the projected mouse position (`u.mouse`). When geometry falls within this field (`u.zoom_params.y`), a localized domain translation pushes the coordinates radially outward, simulating the flora parting.

### Color Mapping / Shading
The base material uses a dark, desaturated teal/indigo with high roughness. The "veins" are achieved by taking the fractional part of scaled spatial coordinates and applying a sharp smoothstep, resulting in emissive, high-contrast neon patterns (electric pink, vivid cyan, lime green). A strong volumetric fog (exponential distance attenuation) gives the scene profound depth.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Neuro-Kinetic Bloom
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    resolution: vec2<f32>,
    mouse: vec2<f32>,
    time: f32,
    config: vec4<f32>,
    zoom_params: vec4<f32>,
    custom_params: vec4<f32>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn map(p: vec3<f32>) -> vec2<f32> {
    var pos = p;
    let mouse_rot = (u.mouse * 2.0 - 1.0) * 3.14;

    let rot_xz = pos.xz * rot(u.time * 0.1 + mouse_rot.x);
    pos.x = rot_xz.x;
    pos.z = rot_xz.y;

    let rot_yz = pos.yz * rot(u.time * 0.05 + mouse_rot.y);
    pos.y = rot_yz.x;
    pos.z = rot_yz.y;

    // Flora Repetition
    let spacing = 6.0;
    var cell = floor(pos / spacing);
    pos = pos - spacing * round(pos / spacing);

    // Audio-reactive Twist
    let twist_amount = 0.5 + sin(u.time * 0.5 + u.config.y) * 0.2;
    let twisted_xy = pos.xy * rot(pos.z * twist_amount);
    pos.x = twisted_xy.x;
    pos.y = twisted_xy.y;

    // Mouse Repulsion
    let mouse_pos = vec3<f32>((u.mouse * 2.0 - 1.0) * 10.0, 0.0);
    let dist_to_mouse = length(p - mouse_pos);
    if (dist_to_mouse < u.zoom_params.y) {
        let push = normalize(p - mouse_pos) * (u.zoom_params.y - dist_to_mouse) * 0.5;
        pos = pos + push;
    }

    let branch_length = 3.0 + sin(u.config.y * 2.0) * u.zoom_params.x;
    let d_branch = sdCapsule(pos, vec3<f32>(0.0, 0.0, -branch_length), vec3<f32>(0.0, 0.0, branch_length), 0.3);

    // Vein displacement
    let vein = sin(pos.z * 10.0 - u.time * 5.0) * sin(atan2(pos.y, pos.x) * 6.0);
    let final_d = d_branch - vein * 0.05 * u.zoom_params.z;

    return vec2<f32>(final_d * 0.5, vein); // Distance and MatID (vein intensity)
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.001;
    return normalize( e.xyy*map( p + e.xyy ).x +
                      e.yyx*map( p + e.yyx ).x +
                      e.yxy*map( p + e.yxy ).x +
                      e.xxx*map( p + e.xxx ).x );
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let dims = textureDimensions(writeTexture);
    if (coords.x >= dims.x || coords.y >= dims.y) { return; }

    let uv = (vec2<f32>(coords) - 0.5 * vec2<f32>(dims)) / f32(dims.y);
    let ro = vec3<f32>(0.0, 0.0, -12.0 + u.zoom_params.w);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var mat_id = 0.0;
    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        if(res.x < 0.001 || t > 50.0) {
            mat_id = res.y;
            break;
        }
        t += res.x;
    }

    var col = vec3<f32>(0.02, 0.05, 0.1); // Deep sea void
    if (t < 50.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let lig = normalize(vec3<f32>(0.8, 0.7, -0.6));
        let dif = clamp(dot(n, lig), 0.0, 1.0);

        let baseColor = vec3<f32>(0.05, 0.1, 0.15);
        let veinColor = vec3<f32>(0.0, 1.0, 0.5) * max(0.0, mat_id) * (2.0 + u.config.y);

        col = baseColor * dif + veinColor * u.zoom_params.z;
        col = mix(col, vec3<f32>(0.01, 0.02, 0.05), 1.0 - exp(-0.02 * t * t));
    }

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Bloom Extension (u.zoom_params.x) - (1.0, 0.0, 5.0, 0.1)
- Repulsion Radius (u.zoom_params.y) - (3.0, 0.0, 10.0, 0.1)
- Vein Glow (u.zoom_params.z) - (1.0, 0.0, 5.0, 0.1)
- Camera Zoom (u.zoom_params.w) - (0.0, -10.0, 10.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
