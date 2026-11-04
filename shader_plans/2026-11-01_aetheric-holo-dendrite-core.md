# New Shader Plan: Aetheric Holo-Dendrite Core

## Overview
A mesmerizing network of glowing holographic dendrites, branching outward and reacting organically to cosmic frequencies and audio inputs.

## Features
- Intricate, multi-branching dendrite geometry generated via Kaleidoscopic Iterated Function Systems (KIFS).
- Dynamic, holographic bloom simulating subsurface scattering and ethereal energy.
- Audio-reactive growth and glow intensity driven by `plasmaBuffer[0]` (bass and treble).
- Mouse interaction: clicking and dragging creates a gravitational spatial warp that bends the fractal branches toward the cursor.
- Iridescent color mapping: shifting between deep aquatic blues and electric pinks based on spatial positioning.
- Metallic highlights and fake specular reflections on the dendrite surfaces for a futuristic cyber-organic feel.

## Technical Implementation
- File: public/shaders/gen-aetheric-holo-dendrite-core.wgsl
- Category: generative
- Tags: ["organic", "holographic", "cyberpunk", "audio-reactive", "interactive"]
- Algorithm: Volumetric raymarching with folded space (KIFS) fractal generation and domain distortion.

### Core Algorithm
The shader will use raymarching to render the geometry. The core structure is formed by repeatedly folding space (using `abs()` and rotations) to create a branching fractal network. A base cylinder or capsule SDF will be evaluated within this folded domain to render the dendrite branches. The space will be continuously rotated over time to create a living, breathing effect.

### Mouse Interaction
When the mouse is clicked (`u.zoom_config.w > 0.5`), a localized spherical distortion will be applied to the domain (`p`). The strength of the warp will be inversely proportional to the distance between `p` and the mapped mouse position (`u.zoom_config.yz`). This creates a localized gravity well that dynamically bends the fractal matrix toward the user's cursor.

### Color Mapping / Shading
The coloring employs fake subsurface scattering approximated by accumulating glow steps during the raymarch. The base surface color transitions smoothly between blue and pink based on the length of the final folded coordinate. Specular highlights provide a metallic, synthetic contrast to the organic shapes. The overall bloom intensity is heavily modulated by the bass (`plasmaBuffer[0].x`) and treble (`plasmaBuffer[0].z`) signals to create a pulsating, audiovisual experience.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Aetheric Holo-Dendrite Core
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
  config: vec4<f32>,              // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,         // .x = time, .yz = mouse_uv (0-1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,         // .xyzw = user params p1..p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

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

fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;

    // Mouse Interaction: Spatial warp when clicked
    if (u.zoom_config.w > 0.5) {
        let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 8.0, (0.5 - u.zoom_config.z) * 8.0, 0.0);
        let dist_to_mouse = length(p - mouse_pos);
        if (dist_to_mouse < 4.0) {
            let pull = 1.0 - smoothstep(0.0, 4.0, dist_to_mouse);
            p = mix(p, mouse_pos, pull * 0.4);
        }
    }

    let time = u.config.x * u.zoom_params.y; // Time driven by Speed param

    // Base rotation
    let rz = rot(time * 0.3);
    p.x = p.x * rz.x + p.y * rz.y;
    p.y = p.x * -rz.y + p.y * rz.x;

    let ry = rot(time * 0.2);
    p.x = p.x * ry.x + p.z * ry.y;
    p.z = p.x * -ry.y + p.z * ry.x;

    // Fractal Folding (KIFS) to generate dendrites
    var scale = 1.0;
    for (var i = 0; i < 5; i++) {
        p = abs(p) - vec3<f32>(0.6, 0.4, 0.5) * u.zoom_params.z; // Fractal Spread

        let rx = rot(PI / 4.0 + sin(time * 0.5) * 0.1);
        p.y = p.y * rx.x + p.z * rx.y;
        p.z = p.y * -rx.y + p.z * rx.x;

        let rz2 = rot(PI / 6.0);
        p.x = p.x * rz2.x + p.y * rz2.y;
        p.y = p.x * -rz2.y + p.y * rz2.x;

        p *= 1.5;
        scale *= 1.5;
    }

    // Dendrite branches (cylinders)
    let dendrite = length(p.xz) - 0.1;
    return dendrite / scale;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) - 0.5 * resolution) / resolution.y;

    let ro = vec3<f32>(0.0, 0.0, -4.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var p = ro;
    var t = 0.0;
    var glow = 0.0;

    for (var i = 0; i < 80; i++) {
        p = ro + rd * t;
        let d = map(p);

        if (d < 0.005) { break; }
        if (t > 12.0) { break; }

        glow += 0.02 / (0.05 + abs(d)); // Subsurface/bloom accumulation
        t += d * 0.7; // Step slightly smaller for fractal details
    }

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    var col = vec3<f32>(0.0);

    // Background
    col += vec3<f32>(0.02, 0.05, 0.1) * (1.0 - length(uv));

    if (t < 12.0) {
        // Base metallic color
        let baseColor = mix(vec3<f32>(0.1, 0.4, 0.8), vec3<f32>(0.9, 0.2, 0.5), clamp(length(p) * 0.2, 0.0, 1.0));

        // Specular/Metallic fake highlight
        let normalDir = normalize(p);
        let spec = pow(max(dot(reflect(rd, normalDir), normalize(vec3<f32>(1.0, 1.0, -1.0))), 0.0), 16.0);

        col = baseColor * 0.5 + vec3<f32>(1.0) * spec * 0.3;
    }

    // Add holographic bloom and audio reactivity
    let bloomIntensity = u.zoom_params.x;
    let audioGlow = vec3<f32>(0.2, 0.6, 1.0) * bass + vec3<f32>(1.0, 0.2, 0.6) * treble;
    col += (vec3<f32>(0.1, 0.3, 0.5) + audioGlow * 0.5) * glow * bloomIntensity * u.zoom_params.w;

    // Output
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)

Bloom Intensity (1.0, 0.0, 3.0, 0.1)
Time Speed (1.0, 0.0, 3.0, 0.1)
Fractal Spread (1.0, 0.5, 2.0, 0.1)
Glow Power (1.0, 0.0, 2.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
