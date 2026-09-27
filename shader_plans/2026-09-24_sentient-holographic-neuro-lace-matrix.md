# New Shader Plan: Sentient Holographic Neuro-Lace Matrix

## Overview
A boundless, hyper-reactive lattice of luminous digital synapses that breathe, think, and evolve, seamlessly blending synthetic cyberpunk aesthetics with organic neural architecture. The vibe is cold corporate cyberspace meets sprawling, bioluminescent alien intelligence.

## Features
- Infinite recursive neural webbing generated via domain-folded SDFs.
- Audio-reactive pulse waves that surge through the lattice like data packets.
- "Thinking" nodes that glow and throb dynamically over time, creating a breathing effect.
- Multi-layered holographic parallax to give deep, stereoscopic volume to the network.
- High-frequency chromatic aberration at the fringes of the lace.
- Liquid-glass refractive shading on the neural strands.

## Technical Implementation
- File: public/shaders/gen-sentient-holographic-neuro-lace-matrix.wgsl
- Category: generative
- Tags: ["cyberpunk", "neural", "lattice", "holographic", "audio-reactive", "organic"]
- Algorithm: 3D Raymarching with heavily domain-repeated and intertwined gyroid/SDF cylinder networks, mapped with audio-reactive displacement.

### Core Algorithm
The environment is built using raymarching. The core volume is a combination of intertwined gyroids and smooth-min'd SDF cylinders that are domain-folded (modulo repetition) to create an infinite lattice. A secondary high-frequency noise displacement is applied along the branches to give them a "ribbed" or "fibrous" texture. Loop-based octaves of noise define the thickness and density of the network, which pulsates based on the audio FFT data.

### Mouse Interaction
The mouse acts as a localized gravity well and data siphon. When hovering, it heavily distorts the local domain, pulling the neural strands towards the cursor, and increasing their luminescent bloom. Clicking triggers a high-speed "overclock" effect, briefly accelerating time and intensifying the chromatic aberration.

### Color Mapping / Shading
The shading utilizes a deep, glass-like refraction model mixed with additive blending for holographic depth. Colors shift dynamically through a gradient of cyan, magenta, and deep indigo. The "nodes" (intersections) emit intense, glowing white/cyan bloom, modulated by audio bass. Specular highlights slide along the strands, driven by the global time variable to mimic flowing data.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Sentient Holographic Neuro-Lace Matrix
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=Param
  zoom_params: vec4<f32>,  // x=Complexity, y=ColorShift, z=GrowthSpeed, w=Specular
  ripples: array<vec4<f32>, 50>,
};

const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Distance estimator for the neuro-lace
fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;

    // Audio reactivity
    let bass = extraBuffer[0];

    // Mouse distortion
    let mousePos = vec3<f32>((u.zoom_config.y - 0.5) * 5.0, (0.5 - u.zoom_config.z) * 5.0, 0.0);
    let distToMouse = length(p - mousePos);
    if (distToMouse < 2.0) {
        // Pull strands towards mouse
        p -= normalize(p - mousePos) * (2.0 - distToMouse) * 0.5;
    }

    // Domain repetition
    let spacing = 2.0;
    p = (fract(p / spacing + 0.5) - 0.5) * spacing;

    // Construct gyroid-like intertwined lattice
    let scale = u.zoom_params.x * 2.0 + 1.0;
    var d = (dot(sin(p * scale), cos(p.zxy * scale)) - 0.5) / scale;

    // Add pulsing thickness
    d -= 0.1 + bass * 0.05 * sin(u.config.x * u.zoom_params.z + p.y * 10.0);

    return d;
}

// Normal calculation
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

// Main compute shader
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) - 0.5 * vec2<f32>(dimensions)) / f32(dimensions.y);

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -3.0 - u.config.x * u.zoom_params.z * 0.5);
    let rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    var p = ro;
    var t = 0.0;
    var steps = 0;
    var hit = false;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * t;
        let d = map(p);
        if (d < SURF_DIST) {
            hit = true;
            steps = i;
            break;
        }
        if (t > MAX_DIST) {
            break;
        }
        t += d;
    }

    var col = vec3<f32>(0.0);

    if (hit) {
        let n = getNormal(p);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let spec = pow(max(dot(reflect(-lightDir, n), -rd), 0.0), 32.0) * u.zoom_params.w;

        let colorShift = u.zoom_params.y;
        let baseColor = vec3<f32>(0.1, 0.5 + colorShift * 0.5, 0.8 - colorShift * 0.3);

        // Ambient occlusion based on steps
        let ao = 1.0 - f32(steps) / f32(MAX_STEPS);

        col = baseColor * diff * ao + spec;
    } else {
        // Background glow
        col = vec3<f32>(0.01, 0.02, 0.05);
    }

    // Post-processing (holographic scanlines)
    col *= 0.9 + 0.1 * sin(uv.y * 100.0 + u.config.x * 5.0);

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)
Complexity (0.5, 0.1, 1.0, 0.01)
ColorShift (0.5, 0.0, 1.0, 0.01)
GrowthSpeed (1.0, 0.1, 5.0, 0.1)
Specular (1.0, 0.0, 2.0, 0.1)