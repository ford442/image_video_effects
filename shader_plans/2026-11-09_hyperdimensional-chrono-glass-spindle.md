# New Shader Plan: Hyperdimensional Chrono-Glass Spindle

## Overview
A mesmerizing, perpetually unwinding spool of translucent, crystalline threads that fold through non-Euclidean geometry, creating an iridescent hourglass of time itself.

## Features
- Interlocking multi-axis spirals rendered in translucent "glass" that refracts underlying layers.
- Chromatic aberration mapping on the edges of the spindle to simulate complex optical properties.
- Temporal dilation: The center of the spindle spins exponentially faster than the outer bands.
- Dynamic iridescence derived from normal vectors and view-angle-dependent thin-film interference.
- Acoustic reactivity driving micro-vibrations in the spindle's crystalline structure.
- Deep space, star-dusted void background that slowly warps around the spindle's gravitational pull.

## Technical Implementation
- File: public/shaders/gen-hyperdimensional-chrono-glass-spindle.wgsl
- Category: generative
- Tags: ["glass", "time", "fractal", "iridescent", "spindle", "non-euclidean"]
- Algorithm: A raymarched scene utilizing recursive domain folding and nested Torus/Helix SDFs to construct a hyper-dimensional spindle.

### Core Algorithm
- **Raymarching**: Standard raymarching loop with dynamic step sizes to handle the glass refraction effects.
- **SDFs**: A core nested helix structure combined with a hyperbolic hourglass shape, created using boolean intersections of rotated tori and stretched cylinders.
- **Domain Repetition**: Polar domain repetition around the central axis to generate the countless threads of the spindle.
- **Fractal Twisting**: A `twist` operation applied iteratively based on the distance from the origin and modulated by time to create the "winding" effect.

### Mouse Interaction
- Mouse X controls the "temporal shear", altering the twist rate of the inner vs outer spindle layers.
- Mouse Y controls the observer's orbital pitch, tilting the spindle on its axis.
- Mouse Down (click) creates a shockwave that temporarily shatters the spindle into fragments that immediately reverse-assemble.

### Color Mapping / Shading
- **Translucency & Refraction**: Simulated using multi-pass interior depth sampling.
- **Iridescence**: Calculated via `dot(normal, view_dir)` mixed with a rainbow color palette to simulate thin-film interference.
- **Chromatic Aberration**: The edges of the spindle displace RGB channels slightly based on distance to the center.
- **Bloom**: Over-exposing the high-intensity reflections along the threads.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Hyperdimensional Chrono-Glass Spindle
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

const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn map(p: vec3<f32>) -> f32 {
    var q = p;

    // Mouse interaction: orbital pitch and temporal shear
    let mouse = u.zoom_config.yz;
    let pitch = (mouse.y - 0.5) * 3.14;

    // Rotate on X axis based on mouse
    var qy = q.y;
    var qz = q.z;
    q.y = qy * cos(pitch) - qz * sin(pitch);
    q.z = qy * sin(pitch) + qz * cos(pitch);

    // Temporal twist
    let t = u.config.x * u.zoom_params.x; // Spindle speed
    let shear = (mouse.x - 0.5) * 5.0;
    let twist = t + q.y * shear + length(q.xz) * u.zoom_params.y; // Winding complexity

    q.x = q.x * cos(twist) - q.z * sin(twist);
    q.z = p.x * sin(twist) + q.z * cos(twist);

    // Spindle shape: hyperboloid using inverted cone + cylinder
    let dCyl = length(q.xz) - (1.0 - abs(q.y)*0.3) * 1.5;

    // Thread details using polar repetition
    let angle = atan2(q.z, q.x);
    let threads = 12.0 * u.zoom_params.z; // Thread density
    let threadD = (cos(angle * threads) * 0.5 + 0.5) * 0.1;

    let d = dCyl - threadD;

    return d * 0.5; // distance underestimation for twist
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

fn getIridescence(normal: vec3<f32>, viewDir: vec3<f32>) -> vec3<f32> {
    let ndotv = max(dot(normal, viewDir), 0.0);
    let phase = ndotv * 3.14159 * 2.0;

    // Spectral color function
    let col = vec3<f32>(
        sin(phase + 0.0) * 0.5 + 0.5,
        sin(phase + 2.09) * 0.5 + 0.5,
        sin(phase + 4.18) * 0.5 + 0.5
    );
    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = u.config.zw;
    if (f32(id.x) >= res.x || f32(id.y) >= res.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    var p = ro;
    var t = 0.0;
    var d = 0.0;
    var iters = 0.0;

    for(var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * t;
        d = map(p);
        if (abs(d) < SURF_DIST || t > MAX_DIST) { break; }
        t += d;
        iters += 1.0;
    }

    var col = vec3<f32>(0.0); // Background void

    if (t < MAX_DIST) {
        let n = getNormal(p);
        let lightPos = vec3<f32>(2.0, 5.0, -3.0);
        let l = normalize(lightPos - p);

        let diff = max(dot(n, l), 0.0);
        let viewDir = normalize(ro - p);

        // Iridescence
        let irid = getIridescence(n, viewDir);

        // Specular
        let h = normalize(l + viewDir);
        let spec = pow(max(dot(n, h), 0.0), 32.0);

        // Base glass color modulated by UI param
        let baseCol = vec3<f32>(0.1, 0.4, 0.8) * u.zoom_params.w;

        // Combine lighting
        col = baseCol * diff + irid * 0.8 + vec3<f32>(spec);

        // Glass glow / inner scattering based on ray iterations
        let scatter = pow(iters / f32(MAX_STEPS), 2.0);
        col += vec3<f32>(0.2, 0.6, 1.0) * scatter;
    } else {
        // Starfield background
        let starNoise = fract(sin(dot(rd.xy, vec2<f32>(12.9898, 78.233))) * 43758.5453);
        if (starNoise > 0.995) {
            col += vec3<f32>(1.0);
        }
    }

    // Gamma correction
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
```

## Parameters (for UI sliders)
- `spindle_speed` (1.0, 0.0, 5.0, 0.1) -> Mapped to `zoom_params.x`
- `winding_complexity` (1.0, 0.1, 3.0, 0.1) -> Mapped to `zoom_params.y`
- `thread_density` (1.0, 0.5, 5.0, 0.1) -> Mapped to `zoom_params.z`
- `glass_tint` (1.0, 0.0, 2.0, 0.1) -> Mapped to `zoom_params.w`

## Integration Steps
1. Create shader file
2. Create JSON definition
3. Run generate_shader_lists.js
4. Upload via storage_manager
