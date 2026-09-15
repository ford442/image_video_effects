# New Shader Plan: Aetherial Clockwork Resonance

## Overview
A mesmerizing, infinitely scaling macro-mechanism of interlocking fractal gears and celestial rings bathed in god-rays. It feels like peering into the heart of a cosmic time-engine.

## Features
- Infinite zooming through nested, rotating geometric arrays
- Metallic SDF clockwork rings that mesh perfectly
- Raymarched volumetric "god-ray" light shafts
- Procedural iridescence applied to gear teeth
- Magnetic mouse interaction that bends the fabric of the time-engine
- Ethereal dust particles suspended in the empty space

## Technical Implementation
- File: public/shaders/gen-aetherial-clockwork-resonance.wgsl
- Category: generative
- Tags: ["clockwork", "fractal", "sdf", "raymarching", "volumetric"]
- Algorithm: Raymarching with domain repetition, rotation matrices for gears, and layered lighting models.

### Core Algorithm
- Uses an SDF raymarcher to render complex, nested tori and cog structures.
- A central `map(p: vec3<f32>)` function combines `sdTorus` and `sdBox` to create gear-like shapes.
- Domain repetition (`p = fract(p * freq) - 0.5`) mixed with rotational transformations (`p.xz *= rot(time)`) gives the illusion of infinitely meshing gears.
- Volumetric lighting is faked by accumulating density samples along the ray path towards a central light source.

### Mouse Interaction
- The mouse position acts as a gravity well.
- When `mouse_down` is true, the `p` vector inside the raymarcher is distorted: `p += normalize(p - mouse_pos) * (1.0 / length(p - mouse_pos)) * intensity`.
- This creates an effect where the gears bend and warp towards the cursor.

### Color Mapping / Shading
- The base material uses a metallic PBR-lite approximation, with high specular highlights and procedural roughness based on noise.
- Iridescence is applied by mapping the view angle (dot product of normal and view ray) to a color palette `a + b*cos(6.28318*(c*t+d))`.
- Bloom/glow is applied in a post-process step or accumulated during raymarching for the ethereal dust.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Aetherial Clockwork Resonance
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Gear Complexity, .y = Rotation Speed, .z = Light Intensity, .w = Iridescence
  ripples: array<vec4<f32>, 50>,
};

// --- CORE FUNCTIONS ---
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}

// Custom gear SDF
fn sdGear(p: vec3<f32>, r1: f32, r2: f32, h: f32, teeth: f32) -> f32 {
    var p2 = p;
    let a = atan2(p2.x, p2.z);
    let r = length(p2.xz);
    let profile = r1 + r2 * sin(a * teeth);
    let d = length(vec2<f32>(r - profile, p2.y)) - h;
    return d;
}

fn map(p: vec3<f32>) -> f32 {
    var p_mod = p;
    // Mouse distortion
    let mouse = u.zoom_config.yz;
    let m_pos = vec3<f32>((mouse - 0.5) * 5.0, 0.0);
    if (u.zoom_config.w > 0.0) {
        let dist = length(p - m_pos);
        p_mod += normalize(p_mod - m_pos) * (0.5 / (dist * dist + 0.1));
    }

    // Domain repetition and rotation
    p_mod.xz *= rot(u.config.x * u.zoom_params.y);
    let complexity = u.zoom_params.x;

    // Combine multiple gears
    let g1 = sdGear(p_mod, 1.0, 0.1, 0.2, 12.0 * complexity);

    // Create nested structure
    var p_inner = p_mod;
    p_inner.xy *= rot(u.config.x * -u.zoom_params.y * 1.5);
    let g2 = sdGear(p_inner, 0.5, 0.05, 0.15, 8.0 * complexity);

    return min(g1, g2);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(e.xyy*map(p + e.xyy) +
                     e.yyx*map(p + e.yyx) +
                     e.yxy*map(p + e.yxy) +
                     e.xxx*map(p + e.xxx));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    let coord = vec2<i32>(global_id.xy);
    if (coord.x >= dimensions.x || coord.y >= dimensions.y) { return; }

    let res = vec2<f32>(dimensions);
    let uv = vec2<f32>(coord) / res;
    let p_uv = (uv - 0.5) * 2.0;
    let p = vec2<f32>(p_uv.x * (res.x / res.y), p_uv.y);

    let ro = vec3<f32>(0.0, 0.0, -3.0);
    let rd = normalize(vec3<f32>(p.x, p.y, 1.0));

    var t = 0.0;
    var d = 0.0;
    for(var i = 0; i < 100; i++) {
        let pos = ro + rd * t;
        d = map(pos);
        if(d < 0.001 || t > 10.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    if (t < 10.0) {
        let pos = ro + rd * t;
        let nor = calcNormal(pos);

        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(nor, lightDir), 0.0);

        // Iridescence based on view angle
        let viewDir = normalize(ro - pos);
        let ndotv = max(dot(nor, viewDir), 0.0);

        // Color palette for iridescence
        let a = vec3<f32>(0.5, 0.5, 0.5);
        let b = vec3<f32>(0.5, 0.5, 0.5);
        let c = vec3<f32>(1.0, 1.0, 1.0);
        let d_pal = vec3<f32>(0.0, 0.33, 0.67);
        let iridescence = a + b * cos(6.28318 * (c * (ndotv * u.zoom_params.w) + d_pal));

        col = iridescence * diff * u.zoom_params.z;
    }

    // Volumetric glow approximation
    col += vec3<f32>(0.1, 0.2, 0.3) * (1.0 / (t * t * 0.1)) * u.zoom_params.z;

    textureStore(writeTexture, coord, vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)
- Gear Complexity (1.0, 0.5, 2.0, 0.1) -> Maps to zoom_params.x
- Rotation Speed (1.0, -2.0, 2.0, 0.1) -> Maps to zoom_params.y
- Light Intensity (1.0, 0.0, 3.0, 0.1) -> Maps to zoom_params.z
- Iridescence (1.0, 0.0, 5.0, 0.1) -> Maps to zoom_params.w
