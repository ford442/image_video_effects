# New Shader Plan: Bioluminescent Cyber-Aether Void-Seahorse

## Overview
A hyper-majestic, biomechanical void-seahorse woven from shattered liquid-aether and pulsing cybernetic bioluminescence, drifting gracefully through a chaotic, fluid-dynamic quantum reef.

## Features
- **Fluid-Dynamic Quantum Reef:** A volumetric backdrop of swirling, dark-matter nebulae that mimics the gentle currents of an abyssal sea.
- **Biomechanical Anatomy:** Intricate cybernetic plating interlocked with shattered crystalline structures along the seahorse's back and tail.
- **Pulsing Bioluminescence:** Internal lighting that glows and shifts in color through its transparent aether-flesh, highly reactive to audio.
- **Prehensile Tail Dynamics:** A curling, fractal-based tail that spirals into a recursive geometric sequence based on time and audio input.
- **Liquid-Aether Dorsal Fin:** A continuously oscillating fin composed of energy waves that distort the space around it.

## Technical Implementation
- File: public/shaders/gen-bioluminescent-cyber-aether-void-seahorse.wgsl
- Category: generative
- Tags: ["organic", "quantum", "biomechanical", "audio-reactive", "fluid", "bioluminescent"]
- Algorithm: Volumetric raymarching with multi-octave FBM for the quantum reef background and complex domain warping/SDF compositions for the biomechanical seahorse structure.

### Core Algorithm
- **SDF Composition:** The seahorse body uses smoothly blended capsule and torus SDFs, modified with a sinewave domain distortion for the organic curve of its spine.
- **Fractal Tail:** A recursive folding algorithm (similar to a Mandelbox or KIFS) applied strictly to the tail region to create the tightly coiled, infinite spiral.
- **Quantum Reef Background:** Multi-layered volumetric raymarching using a 3D FBM noise function to create fluid-like density variations and dark-matter clouds.
- **Bioluminescence:** The internal glow is achieved using subsurface scattering approximations (transmittance mapping) and emissive volumetric accumulation inside the main SDF shape.
- **Audio Reactivity:** Bass frequencies (`plasmaBuffer[0].x`) drive the intensity of the bioluminescent glow and the oscillation frequency of the liquid-aether dorsal fin.

### Mouse Interaction
- The seahorse gracefully tracks the mouse coordinates (`let mouse = u.zoom_config.yz;`), slowly reorienting its gaze and posture towards the cursor with a smooth, damped spring physics feel.
- The quantum reef currents softly distort and part around the cursor's position, creating a localized gravity well.

### Color Mapping / Shading
- **Palette:** Deep abyssal indigos and void-blacks contrast with vibrant, glowing neon cyans, bioluminescent greens, and aether-magentas.
- **Materials:** The cybernetic plating uses a high-gloss, metallic BRDF with intense chromatic dispersion, while the organic components use a highly scattering, gelatinous volumetric shader.
- **Bloom & Glow:** Extensive post-processing bloom applied specifically to the emissive bioluminescent channels to create an intense, ethereal aura.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Bioluminescent Cyber-Aether Void-Seahorse
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var<storage, read> touchBuffer: array<Touch>;
@group(0) @binding(5) var<storage, read> waveformBuffer: array<f32>;
@group(0) @binding(6) var<storage, read> freqBuffer: array<f32>;
@group(0) @binding(7) var<storage, read> audioHistoryBuffer: array<f32>;
@group(0) @binding(8) var<storage, read> plasmaBuffer: array<vec4<f32>>;
@group(0) @binding(9) var depthTexture: texture_depth_2d;
@group(0) @binding(10) var readDepthTexture: texture_depth_2d;
@group(0) @binding(11) var non_filtering_sampler: sampler;
@group(0) @binding(12) var<storage, read_write> extraBuffer: array<f32>;

struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    frame: u32,
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    view_matrix: mat4x4<f32>,
    proj_matrix: mat4x4<f32>,
    camera_pos: vec3<f32>,
}

struct Touch {
    pos: vec2<f32>,
    vel: vec2<f32>,
    force: f32,
    radius: f32,
    id: i32,
    phase: i32,
}

// ----------------------------------------------------------------
// SDF Primitives & Operations
// ----------------------------------------------------------------
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn rotate(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ----------------------------------------------------------------
// Noise & Volumetrics
// ----------------------------------------------------------------
fn hash33(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453123);
}

fn fbm(p: vec3<f32>) -> f32 {
    // Basic 3D FBM implementation
    var f = 0.0;
    var w = 0.5;
    var x = p;
    for (var i = 0; i < 4; i++) {
        f += w * (hash33(x).x - 0.5);
        w *= 0.5;
        x *= 2.0;
    }
    return f;
}

// ----------------------------------------------------------------
// Mapping & Raymarching
// ----------------------------------------------------------------
fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;
    let t = u.time * u.config.w; // Evolution speed
    let bass = plasmaBuffer[0].x * u.config.y; // Audio reactivity
    let mouse = u.zoom_config.yz;

    // Distort space via mouse interaction
    p -= vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0);

    // Space curving for Seahorse spine
    p.x += sin(p.y * 2.0 + t) * 0.2;

    // Core Seahorse Body SDF
    let d_body = length(p - vec3<f32>(0.0, 0.0, 0.0)) - 1.0;

    // Fractal Tail
    var p_tail = p + vec3<f32>(0.0, 1.5, 0.0);
    for (var i = 0; i < 4; i++) {
        p_tail.xy *= rotate(0.5);
        p_tail = abs(p_tail) - vec3<f32>(0.2);
    }
    let d_tail = length(p_tail) - 0.1;

    let final_d = smin(d_body, d_tail, 0.5);

    // Material ID: 1 for body, 2 for tail
    return vec2<f32>(final_d, 1.0);
}

// ----------------------------------------------------------------
// Main Compute
// ----------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let uv = vec2<f32>(global_id.xy) / vec2<f32>(dims);

    // Setup Ray
    var ro = vec3<f32>(0.0, 0.0, 5.0);
    var rd = normalize(vec3<f32>((uv - 0.5) * 2.0, -1.0));

    // Raymarching Loop
    var t = 0.0;
    var mat = 0.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if (d.x < 0.001) {
            mat = d.y;
            break;
        }
        t += d.x;
        if (t > 20.0) { break; }
    }

    // Shading
    var col = vec3<f32>(0.0); // Background void color

    if (t < 20.0) {
        let p = ro + rd * t;

        // Base color
        let baseColor = vec3<f32>(0.1, 0.5, 0.8);
        let glowColor = vec3<f32>(0.0, 1.0, 0.5);
        let bass = plasmaBuffer[0].x * u.config.y;

        col = mix(baseColor, glowColor, sin(u.time * 2.0) * 0.5 + 0.5 + bass);
    } else {
        // Volumetric quantum reef background
        col += vec3<f32>(fbm(ro + rd * 5.0)) * vec3<f32>(0.1, 0.0, 0.2);
    }

    // Final color modification (Brightness mapping)
    col *= u.config.z;

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, 1.0));
}
```

## Parameters (for UI sliders)

- Evolution Speed (1.0, 0.1, 5.0, 0.1)
- Audio Reactivity (1.0, 0.0, 3.0, 0.1)
- Void Intensity (0.5, 0.0, 1.0, 0.05)
- Bioluminescent Shift (0.0, -1.0, 1.0, 0.1)