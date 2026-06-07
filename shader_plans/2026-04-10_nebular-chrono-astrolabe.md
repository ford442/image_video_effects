# New Shader Plan: Nebular Chrono-Astrolabe

## Overview
A colossal, ancient cosmic astrolabe forged from iridescent stardust and glowing quantum gears, endlessly rotating and re-aligning to map the shifting geometry of time and sound.

## Features
- Intricate, intersecting orbital rings of glowing plasma and crystalline metallic structures.
- Audio-reactive gear rotation speeds and volumetric light bursts (`u.config.y`).
- Gravity-well mouse interactions that pull and distort the astrolabe rings.
- Chromatic dispersion on the crystalline elements with a deep space, star-field background.
- KIFS fractals embedded within the gear teeth to create infinitely complex mechanisms.
- Time-based shifting of the orbital axes to create constantly evolving geometric alignments.

## Technical Implementation
- File: public/shaders/gen-nebular-chrono-astrolabe.wgsl
- Category: generative
- Tags: ["cosmic", "mechanical", "quantum", "raymarching", "audio-reactive"]
- Algorithm: Raymarching with nested rotational matrices, torus/cylinder SDFs, and KIFS fractals.

### Core Algorithm
The scene is built using a raymarching loop evaluating a complex SDF. The primary structures are nested, rotated torus and cylinder SDFs representing the astrolabe rings and gears. Each ring's rotation matrix is driven by `u.config.x` (Time) and modified by `u.config.y` (Audio). The gear teeth are generated using a 3D KIFS fold to create intricate, repeating geometric details along the rims. A subtle domain warp is applied to the background space using FBM noise to simulate a nebular dust cloud.

### Mouse Interaction
The mouse (`u.zoom_config.y`, `u.zoom_config.z`) creates a localized gravity well. Rays passing near the mouse position undergo a spatial distortion, bending their trajectories towards the point. This causes the astrolabe rings to visually stretch and warp when the mouse moves over them, simulating a localized black hole effect.

### Color Mapping / Shading
The metallic structures use a Blinn-Phong shading model with a high specular exponent for sharp highlights, tinted with iridescent colors (shifting based on the normal and view angle). A strong bloom effect is simulated by accumulating emissive energy along the ray path (volumetric scattering) near the plasma cores. Chromatic dispersion is approximated by separating color channels slightly during the refraction/reflection calculations on the crystalline components.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Nebular Chrono-Astrolabe
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
    config: vec4<f32>, // x: Time, y: Audio/Click, z: ResX, w: ResY
    zoom_config: vec4<f32>, // x: ZoomTime, y: MouseX, z: MouseY, w: Gen
    zoom_params: vec4<f32>, // Sliders mapping
    ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

// --- SDF Primitives ---
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// --- Transformations ---
fn rot2D(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// --- Map Function ---
fn map(p: vec3<f32>) -> vec2<f32> {
    var d = MAX_DIST;
    var mat_id = 0.0;

    var p1 = p;
    // Apply mouse gravity well
    let mouse_pos = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (0.5 - u.zoom_config.z) * 5.0, 0.0);
    let dist_to_mouse = length(p1 - mouse_pos);
    p1 += normalize(mouse_pos - p1) * (1.0 / (dist_to_mouse * dist_to_mouse + 1.0)) * u.zoom_params.w;

    // Inner Core
    var p_core = p1;
    p_core.xy = rot2D(u.config.x * u.zoom_params.x) * p_core.xy;
    let core = length(p_core) - 0.5;

    // Astrolabe Rings
    var p_ring1 = p1;
    p_ring1.yz = rot2D(u.config.x * 0.5 + u.config.y * 2.0) * p_ring1.yz;
    let ring1 = sdTorus(p_ring1, vec2<f32>(1.5, 0.1));

    d = min(core, ring1);
    if (d == core) { mat_id = 1.0; }
    else if (d == ring1) { mat_id = 2.0; }

    return vec2<f32>(d, mat_id);
}

// --- Raymarch ---
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var dO = 0.0;
    var mat = 0.0;
    for(var i=0; i<MAX_STEPS; i++) {
        let p = ro + rd * dO;
        let dS = map(p);
        dO += dS.x;
        mat = dS.y;
        if(dO > MAX_DIST || abs(dS.x) < SURF_DIST) { break; }
    }
    return vec2<f32>(dO, mat);
}

// --- Normals ---
fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let d = map(p).x;
    let e = vec2<f32>(0.001, 0.0);
    let n = d - vec3<f32>(
        map(p - e.xyy).x,
        map(p - e.yxy).x,
        map(p - e.yyx).x
    );
    return normalize(n);
}

// --- Main Compute ---
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(id.xy) * 2.0 - res) / res.y;

    if (f32(id.x) >= res.x || f32(id.y) >= res.y) { return; }

    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    let rm = raymarch(ro, rd);
    let d = rm.x;
    let mat = rm.y;

    var col = vec3<f32>(0.0);

    if (d < MAX_DIST) {
        let p = ro + rd * d;
        let n = getNormal(p);
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);

        if (mat == 1.0) {
            col = vec3<f32>(0.2, 0.8, 1.0) * diff + vec3<f32>(0.0, 0.4, 0.8); // Core
        } else if (mat == 2.0) {
            col = vec3<f32>(1.0, 0.8, 0.2) * diff + vec3<f32>(0.8, 0.4, 0.0); // Rings
        }
    } else {
        col = vec3<f32>(0.01, 0.02, 0.05); // Background
    }

    // Output
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
```

## UI Parameters
Parameters (for UI sliders)

Name (default, min, max, step)
- Rotation Speed: `u.zoom_params.x` (1.0, 0.1, 5.0, 0.1)
- Complexity: `u.zoom_params.y` (2.0, 1.0, 5.0, 1.0)
- Glow Intensity: `u.zoom_params.z` (1.0, 0.0, 3.0, 0.1)
- Gravity Well Strength: `u.zoom_params.w` (0.5, 0.0, 2.0, 0.1)

## Integration Steps

1. Create shader file `public/shaders/gen-nebular-chrono-astrolabe.wgsl`
2. Create JSON definition `shader_definitions/generative/gen-nebular-chrono-astrolabe.json`
3. Run `node scripts/generate_shader_lists.js`
4. Upload via `storage_manager`
