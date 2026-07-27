# New Shader Plan: Resonant Quantum-Obsidian Astro-Manta

## Overview
A colossal, biomechanical manta ray forged from fractured quantum-obsidian and liquid neon-aether, gliding effortlessly through a chaotic, fluid-dynamic acoustic dark matter sea. Its majestic wings leave sprawling trails of fractal bioluminescence that react violently to sub-bass frequencies, illuminating the void as it swims through rippling dimensional currents.

## Features
- **Fractured Obsidian Armor:** Ray-marched, faceted geometric plating with chromatic aberration and sub-surface scattering simulating dark glass.
- **Bioluminescent Veins:** Pulsing trails of neon-aether running through the manta's structure, responding aggressively to audio bass.
- **Fluid-Dynamic Wake:** The manta displaces the volumetric dark matter sea, leaving swirling, acoustic-reactive particle wakes.
- **Quantum Rift Undulation:** Realistic yet hyper-stylized biological swimming motion using complex sine wave modulation mapped to 3D space.
- **Interactive Gravitational Vortex:** Mouse interactions distort the local spacetime, bending the manta's path and twisting the surrounding nebula.

## Technical Implementation
- File: public/shaders/gen-resonant-quantum-obsidian-astro-manta.wgsl
- Category: generative
- Tags: ["organic", "biomechanical", "quantum", "cosmic", "audio-reactive", "raymarching"]
- Algorithm: Volumetric Raymarching with FBM fluid displacement, smooth-min SDFs for organic geometry, and domain warping for the dark matter sea.

### Core Algorithm
- **SDFs:** Base manta shape using modified capped cones and smooth-min blended ellipsoids, intersected with voronoi-based faceted cuts for the obsidian armor.
- **Domain Warping:** 3D FBM noise applied to the spatial coordinates to simulate the fluid-dynamic dark matter nebula.
- **Animation:** Time-based sine waves applied to the wing vertices in the SDF for the undulating swimming motion.

### Mouse Interaction
- The mouse position acts as a temporary gravitational singularity.
- Coordinate transformation: `p -= normalize(p - mouse_pos) * smoothstep(0.0, 2.0, length(p - mouse_pos)) * u_gravity_strength;`
- Pulls the manta slightly off-course and warps the surrounding fluid domain.

### Color Mapping / Shading
- **Obsidian:** Low albedo, high specularity, with fake chromatic dispersion on the edges using varied index-of-refraction lookups.
- **Bioluminescence:** High-intensity neon cyan and purple emissive lighting, multiplied by `plasmaBuffer[0].x` for audio reactivity.
- **Background:** Volumetric scattering calculation using accumulated density of FBM clouds, tinted deep void-blue.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Resonant Quantum-Obsidian Astro-Manta
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var<storage, read> audioBuffer: array<f32>;
@group(0) @binding(5) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(6) var<storage, read> plasmaBuffer: array<vec4<f32>>;
@group(0) @binding(7) var<storage, read> touchBuffer: array<Touch>;
@group(0) @binding(8) var depthTexture: texture_depth_2d;
@group(0) @binding(9) var u_sampler_non_filtering: sampler;
@group(0) @binding(10) var readTexture1: texture_2d<f32>;
@group(0) @binding(11) var readTexture2: texture_2d<f32>;
@group(0) @binding(12) var readDepthTexture: texture_2d<f32>;

struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    frame: u32,
    mouse: vec2<f32>,
    mouse_buttons: u32,
    config: vec4<f32>,
    // x: time scale
    // y: audio reaction multiplier
    // z: brightness multiplier
    // w: evolution speed
}

struct Touch {
    pos: vec2<f32>,
    force: f32,
    id: u32,
}

// Math Constants
const PI = 3.14159265359;

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Main SDF
fn map(p: vec3<f32>) -> f32 {
    var p_mod = p;

    // Mouse Interaction
    let mouse = touchBuffer[0].pos;
    let mouse_world = vec3<f32>((mouse.x - 0.5) * 10.0, -(mouse.y - 0.5) * 10.0, 0.0);
    let dist_to_mouse = length(p - mouse_world);
    if (touchBuffer[0].force > 0.0) {
        p_mod -= normalize(p - mouse_world) * smoothstep(3.0, 0.0, dist_to_mouse);
    }

    // Manta shape logic (simplified for skeleton)
    let body = length(p_mod * vec3<f32>(1.0, 3.0, 0.5)) - 1.0;

    // Wing undulation
    let wing_wave = sin(p_mod.x * 2.0 - u.time * 3.0 * u.config.x) * 0.5 * p_mod.x;
    p_mod.y += wing_wave;

    let wings = length(p_mod * vec3<f32>(0.2, 10.0, 1.0)) - 0.5;

    return smin(body, wings, 0.8);
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coord = vec2<i32>(global_id.xy);
    if (coord.x >= i32(u.resolution.x) || coord.y >= i32(u.resolution.y)) {
        return;
    }

    let uv = (vec2<f32>(coord) - 0.5 * u.resolution) / u.resolution.y;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching
    var t = 0.0;
    var p = ro;
    var hit = false;

    for (var i = 0; i < 100; i++) {
        p = ro + rd * t;
        let d = map(p);
        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t > 20.0) { break; }
        t += d;
    }

    // Shading
    var col = vec3<f32>(0.05, 0.0, 0.1); // Void background

    if (hit) {
        let n = calcNormal(p);
        let light = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, light), 0.0);

        // Audio reactivity from plasma buffer
        let audioBass = plasmaBuffer[0].x * u.config.y;

        // Obsidian base + glowing veins
        let baseColor = vec3<f32>(0.1);
        let glowColor = vec3<f32>(0.2, 0.8, 1.0) * audioBass * 2.0;

        // Fake vein pattern based on position
        let veins = smoothstep(0.8, 1.0, sin(p.x * 10.0) * sin(p.z * 10.0));

        col = baseColor * diff + glowColor * veins;
    }

    // Volumetric fog/bloom overlay
    col += vec3<f32>(0.1, 0.3, 0.5) * (1.0 - exp(-0.05 * t)) * u.config.z;

    textureStore(writeTexture, coord, vec4<f32>(col, 1.0));
}
```

### Parameters (for UI sliders)
- **Time Scale** (1.0, 0.1, 5.0, 0.1) - Controls the speed of the Manta's swimming animation.
- **Audio Reactivity** (1.0, 0.0, 3.0, 0.1) - Multiplier for how intensely the bioluminescence reacts to the bass.
- **Brightness** (1.0, 0.1, 3.0, 0.1) - Overall emission and bloom strength.
- **Evolution Speed** (1.0, 0.0, 5.0, 0.1) - Speed of the dark matter fluid nebula shifting in the background.
## Integration Steps
- [ ] Create shader file
- [ ] Create JSON definition
- [ ] Run generate_shader_lists.js
- [ ] Upload via storage_manager
