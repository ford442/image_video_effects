# New Shader Plan: Radiant Aether Dragon Scale Matrix

## Overview
A hyper-dimensional shifting tessellation of luminescent, iridescent dragon scales that pulse with rippling plasma energy.

## Features
- Dynamic non-Euclidean Voronoi scaling tessellation
- Subsurface scattering iridescence mimicking ancient dragon scales
- Ripple-responsive energy pulses surging along the seams
- Gravity-well mouse interactions that warp the scale geometry
- Ethereal bioluminescent color shifts tied to time oscillations

## Technical Implementation
- File: public/shaders/gen-radiant-aether-dragon-scale-matrix.wgsl
- Category: generative
- Tags: ["tessellation", "iridescence", "plasma", "organic"]
- Algorithm: Raymarching layered with domain repetition, perturbed by multi-octave simplex noise for geometric displacement.

### Core Algorithm
A specialized domain-repetition raymarching setup evaluates a Voronoi-based SDF. The distances are displaced using a 3D simplex noise function to create overlapping, scale-like structures. Each scale incorporates a smooth-min blend with its neighbors to mimic organic, interlocking growth.

### Mouse Interaction
The scales react to `u.zoom_config.w > 0.5`. When the mouse is clicked, the `u.zoom_config.yz` coordinates act as a powerful gravity well, distorting the local SDF coordinate space in a whirlpool-like vortex effect, pulling nearby scales into an orbital pattern.

### Color Mapping / Shading
A custom metallic lighting model with simulated subsurface scattering. Color palettes are driven by dot products of normals and view vectors (Fresnel), resulting in iridescent hues that transition from deep amethyst to blazing aetheric gold.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Radiant Aether Dragon Scale Matrix
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

// --- SHADER CODE START ---
fn hash(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453123);
}

// 3D Simplex noise
fn snoise(v: vec3<f32>) -> f32 {
    return hash(v); // Placeholder for actual implementation
}

// Organic scale smooth-min blend
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn sdf_scale(p: vec3<f32>) -> f32 {
    // Basic scale shape (ellipsoid-like)
    return length(p * vec3<f32>(1.0, 2.0, 0.5)) - 1.0;
}

fn map(p: vec3<f32>) -> f32 {
    var pos = p;

    // Mouse Interaction: Gravity well distortion
    if (u.zoom_config.w > 0.5) {
        let mouse_pos = vec3<f32>((u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(u.config.z / u.config.w, 1.0), 0.0);
        let dist = length(pos.xy - mouse_pos.xy);
        let vortex_strength = u.zoom_params.w;
        let angle = vortex_strength / (dist + 0.1);
        let s = sin(angle);
        let c = cos(angle);
        pos.x = pos.x * c - pos.y * s;
        pos.y = pos.x * s + pos.y * c;
    }

    // Domain repetition
    let scale_density = u.zoom_params.x;
    let grid = floor(pos * scale_density);
    let local_pos = fract(pos * scale_density) - 0.5;

    // Noise displacement for organic feel
    let noise = snoise(grid * 0.1 + u.config.x * 0.5) * 0.5;

    return sdf_scale(local_pos) + noise;
}

fn get_normal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.zw);
    let uv = vec2<f32>(id.xy) / dims;
    let p = uv * 2.0 - 1.0;

    if (id.x >= u32(dims.x) || id.y >= u32(dims.y)) {
        return;
    }

    // Raymarching setup
    var ro = vec3<f32>(0.0, 0.0, -5.0);
    var rd = normalize(vec3<f32>(p * vec2<f32>(dims.x / dims.y, 1.0), 1.0));
    var t = 0.0;

    for (var i = 0; i < 100; i++) {
        let p_march = ro + rd * t;
        let d = map(p_march);
        if (d < 0.001 || t > 20.0) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);

    if (t < 20.0) {
        let p_hit = ro + rd * t;
        let n = get_normal(p_hit);
        let v = -rd;

        // Lighting & Color Mapping (Iridescence & Plasma)
        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 3.0);
        let iridescence = mix(vec3<f32>(0.5, 0.0, 0.8), vec3<f32>(1.0, 0.8, 0.2), fresnel + sin(u.config.x * 2.0)*0.2);

        let plasma = (sin(p_hit.x * 10.0 + u.config.x * 5.0) + cos(p_hit.y * 10.0 + u.config.x * 3.0)) * 0.5 + 0.5;
        col = iridescence * (0.5 + plasma * u.zoom_params.z);
    }

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)

Scale Density (5.0, 1.0, 10.0, 0.1)
Iridescence Shift (0.5, 0.0, 1.0, 0.01)
Plasma Intensity (1.0, 0.0, 5.0, 0.1)
Vortex Strength (2.0, 0.1, 5.0, 0.1)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
