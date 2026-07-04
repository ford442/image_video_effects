# New Shader Plan: Ethereal Chrono-Plasma Void-Manta

## Overview
A majestic, hyper-organic cybernetic space-manta ray gliding through a dark-matter ocean, its translucent biomimetic wings rippling with shifting auroral temporal energy as it consumes deep acoustic bass frequencies.

## Features
- **Volumetric Translucent Biomimicry:** The manta's wings are constructed from layered, procedural SDFs combined with subsurface scattering approximations to create glowing, jelly-like chrono-glass.
- **Audio-Reactive Temporal Ripples:** Low frequencies (bass) generate expanding ripple waves along the wings, simulating temporal distortions cascading through the manta's body.
- **Dark-Matter Ocean Fluidity:** The background environment uses multi-octave swirling noise to simulate a fluid, viscous dark-matter nebula that the manta interacts with.
- **Bioluminescent Neural Pathways:** Glowing, branching fractal lines trace along the manta's back, acting as a dynamic visual equalizer for mid and high acoustic frequencies.
- **Chrono-Distortion Wake:** As the manta moves, it leaves behind a slowly fading trail of chromatic aberration and twisted domain space, representing a tear in time.

## Technical Implementation
- File: public/shaders/gen-ethereal-chrono-plasma-void-manta.wgsl
- Category: generative
- Tags: ["organic", "quantum", "cosmic", "bioluminescence", "audio-reactive", "manta", "temporal"]
- Algorithm: A combination of organic SDF blending (smin) for the manta's body, layered domain warping for the wings, and 3D fluid noise for the surrounding dark-matter ocean, all heavily modulated by audio data to create a living, breathing entity.

### Core Algorithm
The manta's core shape is formed using a flattened, elongated sphere SDF, blended (via smooth minimum) with thinner, expansive wing shapes created by displacing a flat plane SDF with low-frequency sine waves and layered Simplex noise. The 'flapping' motion is achieved by modulating the Z and Y coordinates based on the X (lateral) position multiplied by time. The dark-matter ocean is rendered using a volumetric raymarching approach with low step counts and high noise density, giving it a thick, cloudy appearance. The bioluminescent pathways are generated using a restricted L-system-like fractal noise, masked to the manta's surface.

### Mouse Interaction
The mouse position acts as a gravity or 'food' source.
- X-axis movement gently rotates the entire scene, allowing inspection of the manta from different angles.
- Y-axis movement controls the intensity of the manta's 'pursuit' – dragging the mouse down increases the flapping speed and elongates the manta's body slightly, simulating a dive. The formula for the dive distortion is `p.z -= smoothstep(0.0, 1.0, u_mouse.y) * 2.0 * sin(p.x * 0.5)`.

### Color Mapping / Shading
The manta uses a base palette of deep abyssal blues and purples. The subsurface scattering effect is faked by calculating the thickness of the SDF at the hit point and mapping it to a bright, glowing cyan-to-magenta gradient. The bioluminescent neural pathways emit pure, high-intensity neon pinks and teals, utilizing a post-process bloom (simulated via multiple light accumulations during raymarching) to make them pop against the dark environment. The chrono-distortion wake uses a slight chromatic shift (offsetting the read position for R, G, and B separately based on noise).

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Ethereal Chrono-Plasma Void-Manta
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
    resolution: vec2<f32>,
    time: f32,
    mouse: vec2<f32>,
    frame: u32,
    audio_data: vec4<f32>, // x: bass, y: mid, z: high, w: overall
    config: vec4<f32>,     // x: time scale, y: audio scale, z: zoom, w: unused
    zoom_config: vec4<f32>,
    ripples: vec4<f32>,
    custom_params: array<vec4<f32>, 4>, // up to 16 custom f32 parameters
}

// Custom Parameters Mapping:
// custom_params[0].x = Manta Speed
// custom_params[0].y = Bio-Luminescence Intensity
// custom_params[0].z = Wing Ripple Frequency
// custom_params[0].w = Dark Matter Density

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// 3D Noise function (placeholder for actual implementation)
fn hash(p: vec3<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x * 0.1031, p.y * 0.1030, p.z * 0.0973));
    p3 = p3 + dot(p3, p3.yxz + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(p + vec3<f32>(0.0, 0.0, 0.0)),
                        hash(p + vec3<f32>(1.0, 0.0, 0.0)), f.x),
                   mix(hash(p + vec3<f32>(0.0, 1.0, 0.0)),
                        hash(p + vec3<f32>(1.0, 1.0, 0.0)), f.x), f.y),
               mix(mix(hash(p + vec3<f32>(0.0, 0.0, 1.0)),
                        hash(p + vec3<f32>(1.0, 0.0, 1.0)), f.x),
                   mix(hash(p + vec3<f32>(0.0, 1.0, 1.0)),
                        hash(p + vec3<f32>(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

// Scene SDF
fn map(p: vec3<f32>) -> vec2<f32> {
    var pos = p;
    let time = u.time * u.config.x * u.custom_params[0].x;
    let audio = u.config.y * u.audio_data.x;

    // Manta motion
    let flap = sin(pos.x * u.custom_params[0].z - time * 3.0) * (pos.x * pos.x) * 0.2;
    pos.y += flap;

    // Core body (flattened sphere)
    let body_d = length(pos / vec3<f32>(1.0, 0.2, 2.0)) - 1.0;

    // Wings (displaced plane)
    let wing_d = pos.y + noise(pos * 2.0 - vec3<f32>(0.0, 0.0, time)) * 0.5 * audio;

    // Blend body and wings
    let manta_d = smin(body_d * 0.5, abs(wing_d) + 0.1, 0.5);

    // Material ID: 1.0 for manta, 0.0 for background
    return vec2<f32>(manta_d, 1.0);
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize( e.xyy*map( p + e.xyy ).x +
					  e.yyx*map( p + e.yyx ).x +
					  e.yxy*map( p + e.yxy ).x +
					  e.xxx*map( p + e.xxx ).x );
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coords = vec2<i32>(id.xy);
    if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) { return; }

    let resolution = vec2<f32>(f32(dims.x), f32(dims.y));
    var uv = (vec2<f32>(id.xy) - 0.5 * resolution) / min(resolution.x, resolution.y);

    let time = u.time * u.config.x;
    let audio = u.audio_data.w * u.config.y;

    // Camera setup
    var ro = vec3<f32>(0.0, 2.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.5));

    // Mouse rotation
    let mouse = (u.mouse / resolution - 0.5) * 6.28;
    ro.yz = rot(-mouse.y) * ro.yz;
    rd.yz = rot(-mouse.y) * rd.yz;
    ro.xz = rot(-mouse.x) * ro.xz;
    rd.xz = rot(-mouse.x) * rd.xz;

    // Raymarching loop
    var t = 0.0;
    var col = vec3<f32>(0.0);
    var hit = false;

    // Background Dark Matter Ocean accumulation
    var bg_density = 0.0;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);

        // Accumulate background density
        bg_density += noise(p * 0.5 + vec3<f32>(time * 0.1)) * u.custom_params[0].w * 0.02;

        if (d.x < 0.001) {
            hit = true;
            // Shading
            let n = calcNormal(p);
            let light = normalize(vec3<f32>(1.0, 2.0, -1.0));
            let diff = max(dot(n, light), 0.0);

            // Subsurface / Bio-luminescence fake
            let thickness = map(p + n * 0.1).x; // sample slightly inside
            let sss = smoothstep(0.0, 0.1, abs(thickness)) * u.custom_params[0].y;

            let base_col = vec3<f32>(0.1, 0.2, 0.5);
            let glow_col = vec3<f32>(0.9, 0.1, 0.7);

            col = base_col * diff + glow_col * sss * (1.0 + audio * 2.0);
            break;
        }
        if (t > 20.0) { break; }
        t += d.x;
    }

    if (!hit) {
        // Deep space / dark matter color
        col = vec3<f32>(0.02, 0.01, 0.05) + vec3<f32>(0.2, 0.1, 0.4) * bg_density;
    }

    // Output
    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)
Manta Speed (1.0, 0.1, 5.0, 0.1)
Bio-Luminescence Intensity (1.0, 0.0, 3.0, 0.1)
Wing Ripple Frequency (2.0, 0.5, 5.0, 0.1)
Dark Matter Density (1.0, 0.0, 2.0, 0.05)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager
