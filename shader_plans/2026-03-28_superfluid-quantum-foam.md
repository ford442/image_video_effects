# New Shader Plan: Superfluid Quantum-Foam

## Overview
A mesmerizing, hyper-turbulent ocean of boiling quantum probability foam, where iridescent hyper-bubbles merge and burst in sync with audio frequencies, releasing flashes of raw cosmic energy.

## Features
- **Hyper-Turbulent Foam:** An infinite expanse of smooth-min blended spheres simulating boiling, zero-viscosity superfluid quantum bubbles.
- **Audio-Reactive Popping:** The foam boils and pops violently in response to the audio beat accumulator (`u.config.y`), creating rapidly collapsing voids.
- **Thin-Film Interference Iridescence:** The surface of the bubbles features a swirling, oily rainbow sheen mapped to the surface normal and viewing angle.
- **Hawking Radiation Bursts:** As bubbles collapse, bright volumetric flashes of neon violet, magenta, and pure white energy burst outward.
- **Mouse-Driven Vortex:** The cursor acts as a localized quantum singularity, drawing bubbles into a swirling, high-density accretion disc.
- **Raymarched Subsurface Translucency:** The dense clusters of foam scatter light internally, providing a soft, ghostly glow beneath the surface layer.

## Technical Implementation
- File: public/shaders/gen-superfluid-quantum-foam.wgsl
- Category: generative
- Tags: ["organic", "quantum", "fluid", "audio-reactive", "raymarching", "volumetric"]
- Algorithm: Raymarching a deeply distorted FBM-driven domain with repeated, smooth-blended spheres and dynamic emission zones.

### Core Algorithm
Uses a 3D grid of domain repetition for `sdSphere` primitives, heavily offset by a low-frequency 3D FBM noise to create varying bubble sizes and irregular, overlapping clusters. An `opSmoothUnion` blends the spheres into a continuous, gloopy surface. The audio accumulator (`u.config.y`) drives a high-frequency noise that rapidly shrinks local spheres, simulating chaotic bursting.

### Mouse Interaction
The mouse cursor (`u.mouse`) projects a 3D gravity well into the volume. When the space falls within the radius (`u.zoom_params.y`), coordinates are radially pulled towards the singularity and rotated around the Y-axis, creating a swirling vortex of stretched bubbles.

### Color Mapping / Shading
The base surface calculates an iridescent thin-film color gradient by passing `dot(N, V)` through a cosine palette, resulting in shifting cyan, magenta, and gold reflections. The internal "popping" energy is rendered by accumulating volumetric emission—bright neon violet and pink—whenever rays pass close to the collapsing bubble centers, mapping the intensity to `u.config.y`.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Superfluid Quantum-Foam
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    mouse: vec4<f32>,
    config: vec4<f32>,
    zoom_params: vec4<f32>,
    custom_params: vec4<f32>,
};

fn hash13(p3: vec3<f32>) -> f32 {
    var p3_mod = fract(p3 * 0.1031);
    p3_mod += dot(p3_mod, p3_mod.yzx + 33.33);
    return fract((p3_mod.x + p3_mod.y) * p3_mod.z);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(p: vec3<f32>) -> vec2<f32> {
    var pos = p;
    pos.x += sin(u.time * 0.2 + u.config.y) * 2.0;

    let spacing = 3.0;
    var cell = floor(pos / spacing);
    pos = pos - spacing * round(pos / spacing);

    // Mouse Vortex
    let mouse_pos = vec3<f32>((u.mouse.xy * 2.0 - 1.0) * 10.0, 0.0);
    let dist_to_mouse = length(p - mouse_pos);
    if (dist_to_mouse < u.zoom_params.y) {
        let pull = normalize(mouse_pos - p) * (u.zoom_params.y - dist_to_mouse) * 0.5;
        pos = pos + pull;
        // Vortex Twist
        let s = sin(dist_to_mouse);
        let c = cos(dist_to_mouse);
        let rot = mat2x2<f32>(c, -s, s, c);
        let xz = pos.xz * rot;
        pos.x = xz.x;
        pos.z = xz.y;
    }

    // Audio-reactive boiling
    let boil = hash13(cell) * sin(u.time * 3.0 + u.config.y * 5.0) * u.zoom_params.x;
    let radius = 1.0 + boil;

    let d = length(pos) - radius;

    // Smooth union for foam look (simulated in isolation, but opSmoothUnion is better across cells)
    return vec2<f32>(d, hash13(cell));
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

    let ro = vec3<f32>(0.0, 0.0, -8.0 + u.time * u.zoom_params.w);
    let rd = normalize(vec3<f32>(uv, 1.0));

    var t = 0.0;
    var mat_id = 0.0;
    var glow = 0.0;

    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);

        // Accumulate volumetric glow for hawking radiation
        if(res.x < 0.5) {
            glow += (0.5 - res.x) * 0.1 * u.zoom_params.z;
        }

        if(res.x < 0.001 || t > 40.0) {
            mat_id = res.y;
            break;
        }
        t += res.x * 0.5; // slow march for soft surfaces
    }

    var col = vec3<f32>(0.02, 0.0, 0.05); // Void background
    if (t < 40.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let v = -rd;

        // Iridescent Thin-Film
        let ndotv = clamp(dot(n, v), 0.0, 1.0);
        let iridescence = 0.5 + 0.5 * cos(6.28318 * (vec3<f32>(1.0, 1.0, 1.0) * ndotv + vec3<f32>(0.0, 0.33, 0.67)));

        let lig = normalize(vec3<f32>(0.8, 0.7, -0.6));
        let dif = clamp(dot(n, lig), 0.0, 1.0);

        let baseColor = mix(vec3<f32>(0.1, 0.1, 0.2), iridescence, 0.6);

        col = baseColor * dif;
        col = mix(col, vec3<f32>(0.02, 0.0, 0.05), 1.0 - exp(-0.02 * t * t));
    }

    // Add hawking radiation glow
    let flash = vec3<f32>(0.8, 0.1, 1.0) * glow * (1.0 + sin(u.config.y * 10.0));
    col += flash;

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
- Boiling Volatility (u.zoom_params.x) - (0.5, 0.0, 2.0, 0.05)
- Vortex Radius (u.zoom_params.y) - (4.0, 0.0, 10.0, 0.1)
- Radiation Glow (u.zoom_params.z) - (1.0, 0.0, 5.0, 0.1)
- Current Speed (u.zoom_params.w) - (0.5, 0.0, 3.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
