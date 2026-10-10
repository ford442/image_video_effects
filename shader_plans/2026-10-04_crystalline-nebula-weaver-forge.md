# New Shader Plan: Crystalline Nebula-Weaver Forge

## Overview
A hyper-dimensional cosmic foundry where fractal glass formations weave starlight into geometric constellations, pulsing with crystalline refractions and deep space iridescence.

## Features
- Evolving 3D fractal crystalline structures based on folding space iterations.
- Volumetric raymarching with dual-phase density for internal glow and external glass surfaces.
- Iridescent chromatic aberration mapping tied to space distortion depth.
- Audio-reactive constellation bursts that spawn localized geometric anomalies.
- Real-time dynamic refraction index calculation for crystal surface rendering.
- Orbiting stardust particle fields driven by strange attractors.

## Technical Implementation
- File: public/shaders/gen-crystalline-nebula-weaver-forge.wgsl
- Category: generative
- Tags: ["cosmic", "crystal", "fractal", "raymarching", "volumetric", "geometric"]
- Algorithm: Raymarching an Apullian-style 3D folded fractal space combined with volumetric emission layers for the nebulous stardust.

### Core Algorithm
Raymarcher utilizing 4D rotation folds to construct the core "anvil" of the forge. The SDF uses KIFS (Kaleidoscopic Iterated Function Systems) to create sharp crystalline geometries. A secondary low-density volumetric step calculates nebulous dust surrounding the hard surface, simulating subsurface scattering and internal cosmic glow.

### Mouse Interaction
Mouse movement (active when clicked via `u.zoom_config.w > 0.0`) shifts the primary 4D rotation angles of the KIFS fractal, causing the crystalline structures to continuously unfold and transform like a hyper-Rubik's cube, while casting localized gravity wells that bend the orbiting stardust.

### Color Mapping / Shading
Deep space background of void purples and navy blues. The crystalline structures feature highly specular reflections and chromatic dispersion (iridescence) along the edges using a custom phase function. Subsurface volumetric glow uses vibrant cyan and magenta gradients mapped from the distance to the center.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Crystalline Nebula-Weaver Forge
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Folding Complexity, .y = Nebula Density, .z = Crystal Refraction, .w = Core Pulse Speed
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 80;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 20.0;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Rotation matrix
fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let s = sin(angle);
    let c = cos(angle);
    let oc = 1.0 - c;
    return mat3x3<f32>(
        oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
        oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
        oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c
    );
}

// Kaleidoscopic Iterated Function System (KIFS) fractal
fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;

    // Apply mouse interaction if active
    if (u.zoom_config.w > 0.0) {
        let mouse_uv = u.zoom_config.yz * 2.0 - 1.0;
        let rot_mouse = rot2D(mouse_uv.x * PI);
        let pxz = p.xz * rot_mouse;
        p = vec3<f32>(pxz.x, p.y, pxz.y);

        let rot_mouse_y = rot2D(mouse_uv.y * PI);
        let pyz = p.yz * rot_mouse_y;
        p = vec3<f32>(p.x, pyz.x, pyz.y);
    }

    // Rotate entire structure slowly
    let t = u.config.x * u.zoom_params.w * 0.2;
    let r_base = rot2D(t);
    let pxz = p.xz * r_base;
    p = vec3<f32>(pxz.x, p.y, pxz.y);

    var scale = 1.0;

    // Complexity mapped to zoom_params.x
    let iters = i32(floor(mix(3.0, 7.0, u.zoom_params.x)));

    for(var i = 0; i < iters; i++) {
        p = abs(p) - vec3<f32>(0.5, 0.4, 0.5) * scale;
        let r = rot2D(PI / 4.0 + t * 0.1);
        let pxy = p.xy * r;
        p = vec3<f32>(pxy.x, pxy.y, p.z);
        let pxz2 = p.xz * rot2D(-PI / 6.0);
        p = vec3<f32>(pxz2.x, p.y, pxz2.y);

        scale *= 0.75;
    }

    let d1 = (length(p) - 0.2 * scale) / scale;

    // Subtractive central void
    let d2 = length(p_in) - 1.5;

    return max(d1, -d2);
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let d = map(p);
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(
        map(p - e.xyy),
        map(p - e.yxy),
        map(p - e.yyx)
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) {
        return;
    }

    let uv = (vec2<f32>(global_id.xy) - 0.5 * res) / res.y;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching
    var t = 0.0;
    var i = 0;
    for(i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if(abs(d) < SURF_DIST || t > MAX_DIST) { break; }
        t += d * 0.8; // Step size reduction for fractal
    }

    var color = vec3<f32>(0.0);

    // Nebula accumulation (volumetric approximation)
    let nebula_density = u.zoom_params.y;
    let nebula_glow = f32(i) / f32(MAX_STEPS) * nebula_density * 2.0;
    let glow_color = vec3<f32>(0.2, 0.5, 1.0) * mix(0.1, 1.0, u.zoom_params.w);

    if (t < MAX_DIST) {
        let p = ro + rd * t;
        let n = getNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let viewDir = normalize(ro - p);

        // Refraction/Iridescence (zoom_params.z)
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 3.0);
        let iridescence = 0.5 + 0.5 * cos(3.0 * p.x + vec3<f32>(0.0, 2.0, 4.0) + t * u.zoom_params.z);

        let spec = pow(max(dot(reflect(-lightDir, n), viewDir), 0.0), 32.0);

        color = diff * vec3<f32>(0.8, 0.9, 1.0) * 0.1 + spec * vec3<f32>(1.0) + fresnel * iridescence;
        color = mix(color, glow_color, 0.3); // Mix with internal glow
    } else {
        // Deep space background with slight gradient
        color = vec3<f32>(0.02, 0.01, 0.05) + length(uv) * vec3<f32>(0.05, 0.02, 0.1);
    }

    // Add volumetric nebula glow
    color += glow_color * nebula_glow;

    // Output mapping
    let out_color = vec4<f32>(color, 1.0);

    textureStore(writeTexture, global_id.xy, out_color);
    textureStore(dataTextureA, global_id.xy, vec4<f32>(p.xyz, f32(i))); // Store positions and steps for debug/post
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / MAX_DIST));
}
```

Parameters (for UI sliders)

Folding Complexity (0.5, 0.0, 1.0, 0.01)
Nebula Density (0.5, 0.0, 1.0, 0.01)
Crystal Refraction (0.5, 0.0, 1.0, 0.01)
Core Pulse Speed (0.5, 0.0, 1.0, 0.01)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
