# New Shader Plan: Prismatic Cyber-Chrono Void-Tortoise

## Overview
A colossal, biomechanical cosmic tortoise forged from shattered prismatic chrono-glass and liquid auroral plasma, drifting slowly through an abyssal quantum sea while bearing a violently glowing, fractal pocket dimension upon its massive shell.

## Features
- **Massive Biomechanical Tortoise:** Constructed using complex smooth-min SDFs that blend rigid, geometric cyber-armor with slowly undulating organic plasma limbs.
- **Fractal Pocket Dimension Shell:** The tortoise's shell houses an intricate Kaleidoscopic Iterated Function System (KIFS) fractal, representing a contained, infinitely looping universe.
- **Audio-Reactive Auroral Plasma:** Viscous, glowing fluid courses through the deep ravines of the tortoise's shell and limbs, flashing intensely with neon cyan and radioactive magenta in sync with sub-bass frequencies.
- **Abyssal Quantum Sea:** A dense, volumetric dark-matter background rendered with multi-layered 3D fractional Brownian motion (fBm), creating a heavy, deep-void atmosphere.
- **Temporal Wake:** As the tortoise moves, it leaves a trail of geometric temporal fractures in the void, modeled by displacing the background noise along its slow trajectory.
- **Subsurface Prismatic Scattering:** The crystalline portions of the cyber-armor aggressively refract the internal pocket dimension's light, creating blazing chromatic aberrations across its surface.
- **Interactive Gravitational Drag:** The cursor acts as a localized supermassive singularity, heavily bending the tortoise's path and causing the pocket dimension fractals to wildly spiral toward the mouse.

## Technical Implementation
- File: public/shaders/gen-prismatic-cyber-chrono-void-tortoise.wgsl
- Category: generative
- Tags: ["tortoise", "cybernetic", "prismatic", "chrono", "fractal", "volumetric", "audio-reactive"]
- Algorithm: Advanced raymarching integrating smooth-min geometric SDFs for the body, a deep KIFS fractal structure for the shell, and volumetric flow-noise for the quantum sea.

### Core Algorithm
The tortoise body is generated using a combination of flattened ellipsoids, tapered cylinders for the flippers, and chamfered boxes for the cybernetic armor, all blended using `opSmoothUnion`.
- The shell utilizes a bounded Kaleidoscopic Iterated Function System (KIFS) to generate its intricate, recursive pocket dimension. The iteration count and folding scales are slightly animated using `u.config.x` (Time).
- The limbs exhibit a slow, rhythmic paddling motion achieved by applying low-frequency sine wave domain distortion to the flipper SDFs.
- The abyssal quantum sea uses a volumetric raymarching pass that accumulates heavy, slowly shifting flow-noise density, completely replacing standard background rendering to simulate a viscous void.

### Mouse Interaction
Cursor position (extracted via `let mouse = u.zoom_config.yz;`) introduces a severe gravitational warp to the domain. The space is twisted using a 3D rotation matrix whose angle is inversely proportional to the distance from `vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0)`. This causes the tortoise's limbs to drag and the shell's fractals to spiral intensely toward the point of interaction.

### Color Mapping / Shading
The tortoise uses a deep, obsidian-glass base material with high specular highlights. The interior pocket dimension and plasma veins employ an emissive gradient (neon cyan to blazing magenta to solar gold) that is multiplicatively modulated by `plasmaBuffer[0].x` for audio reactivity. A heavy bloom pass is simulated by accumulating glow from steps close to the surface but not hitting it.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Prismatic Cyber-Chrono Void-Tortoise
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var<storage, read> audioBuffer: array<f32>;
@group(0) @binding(5) var<storage, read> plasmaBuffer: array<vec4<f32>>;
@group(0) @binding(6) var<storage, read> particleBuffer: array<Particle>;
@group(0) @binding(7) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(8) var u_sampler_non_filtering: sampler;
@group(0) @binding(9) var readDepthTexture: texture_depth_2d;
@group(0) @binding(10) var readNormalTexture: texture_2d<f32>;
@group(0) @binding(11) var readPositionTexture: texture_2d<f32>;
@group(0) @binding(12) var readVelocityTexture: texture_2d<f32>;

struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    mouse: vec2<f32>,
    config: vec4<f32>, // Time, Audio Reactivity, Brightness, Evolution Speed
    zoom_config: vec4<f32>, // Zoom, MouseX, MouseY, Custom
}

struct Particle {
    position: vec4<f32>,
    velocity: vec4<f32>,
    color: vec4<f32>,
    life: f32,
}

// 3D Rotation Matrix Function
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

// Smooth Minimum for organic blending
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// KIFS Fractal for the shell's pocket dimension
fn kifs(p: vec3<f32>, time: f32) -> f32 {
    var z = p;
    var scale = 1.0;
    for (var i = 0; i < 4; i++) {
        z = abs(z) - vec3<f32>(0.5, 0.5, 0.5);
        z = z * rot3D(normalize(vec3<f32>(1.0, 1.0, 1.0)), time * 0.1);
        z = z * 2.0;
        scale = scale * 2.0;
    }
    return (length(z) - 1.0) / scale;
}

// Main SDF Map
fn map(p: vec3<f32>, time: f32, audio_reactivity: f32, mouse: vec2<f32>) -> vec2<f32> {
    var p_distorted = p;

    // Gravitational Drag from mouse
    let mouse_pos = vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0);
    let dist_to_mouse = length(p - mouse_pos);
    if (dist_to_mouse > 0.0) {
        let twist_angle = 1.0 / (dist_to_mouse + 0.5) * 2.0;
        p_distorted = p_distorted * rot3D(normalize(mouse_pos + vec3<f32>(0.0, 0.0, 1.0)), twist_angle);
    }

    // Tortoise Body Base
    let body = length(p_distorted * vec3<f32>(1.0, 2.0, 1.0)) - 1.5;

    // Tortoise Shell (Pocket Dimension)
    let shell_base = length(p_distorted * vec3<f32>(1.0, 1.5, 1.0) - vec3<f32>(0.0, 0.5, 0.0)) - 1.6;
    let shell_fractal = kifs(p_distorted, time);
    let shell = max(shell_base, shell_fractal * 0.5);

    // Blending body and shell
    let tortoise = smin(body, shell, 0.3);

    // Material IDs
    var mat_id = 1.0; // Body
    if (shell < body) {
        mat_id = 2.0; // Shell
    }

    return vec2<f32>(tortoise, mat_id);
}

// Raymarching Loop
fn raymarch(ro: vec3<f32>, rd: vec3<f32>, time: f32, audio_reactivity: f32, mouse: vec2<f32>) -> vec2<f32> {
    var t = 0.0;
    var mat_id = 0.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p, time, audio_reactivity, mouse);
        if (d.x < 0.001) {
            mat_id = d.y;
            break;
        }
        if (t > 20.0) {
            break;
        }
        t += d.x;
    }
    return vec2<f32>(t, mat_id);
}

// Main compute shader entry point
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let resolution = u.resolution;
    if (f32(id.x) >= resolution.x || f32(id.y) >= resolution.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) / resolution.xy) * 2.0 - 1.0;
    let aspect = resolution.x / resolution.y;
    let screen_uv = vec2<f32>(uv.x * aspect, uv.y);

    let time = u.config.x;
    let audio_bass = plasmaBuffer[0].x;
    let mouse = u.zoom_config.yz;

    // Camera setup
    let ro = vec3<f32>(0.0, 0.0, 5.0);
    let rd = normalize(vec3<f32>(screen_uv, -1.5));

    // Raymarching
    let result = raymarch(ro, rd, time, audio_bass, mouse);
    let t = result.x;
    let mat_id = result.y;

    var color = vec3<f32>(0.0); // Background void

    if (t < 20.0) {
        // Shading based on mat_id
        if (mat_id == 1.0) {
            // Body shading (obsidian-glass)
            color = vec3<f32>(0.1, 0.15, 0.2);
        } else if (mat_id == 2.0) {
            // Shell shading (fractal emissive)
            let emissive_color = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), sin(time + t * 5.0) * 0.5 + 0.5);
            color = emissive_color * (1.0 + audio_bass * 2.0);
        }
    }

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(color, 1.0));
}
```

## Parameters (for UI sliders)
- Time (1.0, 0.0, 10.0, 0.1)
- Audio Reactivity (1.0, 0.0, 5.0, 0.1)
- Brightness (1.0, 0.0, 3.0, 0.05)
- Evolution Speed (1.0, 0.1, 5.0, 0.1)
