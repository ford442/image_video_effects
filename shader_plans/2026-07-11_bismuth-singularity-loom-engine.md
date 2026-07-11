# New Shader Plan: Bismuth Singularity-Loom Engine

## Overview
A hyper-dimensional, continually self-assembling bismuth crystal matrix orbiting a microscopic gravitational singularity, its iridescent geometric steps carving sharp staircases into the fabric of spacetime. The scene blends hard-edged, prismatic synthetic-architecture with chaotic fluid distortions driven by an intense sub-bass core.

## Features
- **Fractal Bismuth SDF:** A complex Signed Distance Field representing a sharply stepped, hopper-crystal structure (like native bismuth) growing infinitely inwards toward a central point.
- **Micro-Singularity Lensing:** A gravitational distortion effect near the center that curves the raymarching paths, warping the background void and stretching the crystal geometry into an event horizon.
- **Iridescent Thin-Film Interference:** Procedural color mapping calculating view-angle dependent chromatic shifts across the sharp, metallic faces of the bismuth lattice.
- **Acoustic Extrusion:** Heavy bass (`u.config.y`) dynamically pushes or retracts entire concentric layers of the hopper-crystal matrix, creating a mechanical breathing motion.
- **Volumetric Ambient Occlusion:** Deep, high-contrast shadowing calculated from SDF step sizes to enhance the sharp, architectural angles of the crystalline structure.
- **Neon Flux Veins:** High-intensity emissive pathways that travel strictly along 90-degree angles across the crystal's surface, acting as liquid-light energy currents.

## Technical Implementation
- File: `public/shaders/gen-bismuth-singularity-loom-engine.wgsl`
- Category: generative
- Tags: ["geometric", "crystal", "iridescent", "singularity", "fractal", "audio-reactive", "bismuth"]
- Algorithm: Raymarching with domain repetition, hard boolean SDF operations, non-linear ray pathing (gravitational lensing), and dot-product-based thin-film interference coloring.

### Core Algorithm
- **SDF Construction:** Uses exact `sdBox` and boolean `max(a, -b)` subtraction operations scaled down iteratively (using a loop or kifs) to carve out the concentric, hollowed-out cubic staircase structure of bismuth.
- **Ray Warping (Lensing):** During the raymarching loop, the ray direction vector (`rd`) is incrementally bent towards the origin `(0,0,0)` based on the inverse square distance, simulating extreme gravity.
- **Domain Warping:** Applies angular repetitions (`atan2(p.z, p.x)`) to arrange the hopper-crystal towers symmetrically around the singularity.

### Mouse Interaction
- The mouse coordinates (`u.zoom_config.y`, `u.zoom_config.z`) adjust the intensity of the singularity's mass (controlling the ray bending strength) and shift the axis of the surrounding neon flux veins.

### Color Mapping / Shading
- **Thin-Film Iridescence:** The color `col` is determined by taking `dot(normal, view_dir)` and feeding it into a procedural cosine color palette (e.g., `a + b*cos(6.28318*(c*t+d))`) to create a vibrant, metallic oil-slick spectrum.
- **Emissive:** The flux veins overlay a bright additive glow based on fractional step distances in the raymarching loop, reacting intensely to `u.config.y`.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Bismuth Singularity-Loom Engine
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// --- CORE LOGIC ---
const MAX_STEPS: i32 = 120;
const MAX_DIST: f32 = 50.0;
const SURF_DIST: f32 = 0.001;

fn rot3D(axis: vec3<f32>, angle: f32) -> mat3x3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    let t = 1.0 - c;
    let x = axis.x; let y = axis.y; let z = axis.z;
    return mat3x3<f32>(
        t*x*x + c,   t*x*y - s*z, t*x*z + s*y,
        t*x*y + s*z, t*y*y + c,   t*y*z - s*x,
        t*x*z - s*y, t*y*z + s*x, t*z*z + c
    );
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn map(p: vec3<f32>) -> vec2<f32> {
    let time = u.config.x;
    let audio = u.config.y;

    // (Implementation of stepped Bismuth hopper-crystal logic via repeated boolean subtractions)

    let d = sdBox(p, vec3<f32>(1.0)); // Placeholder base shape
    return vec2<f32>(d, 1.0); // dist, material_id
}

fn raymarching(ro: vec3<f32>, rd_in: vec3<f32>) -> vec4<f32> {
    var dO: f32 = 0.0;
    var col: vec3<f32> = vec3<f32>(0.0);
    var p = ro;
    var rd = rd_in;

    for(var i: i32 = 0; i < MAX_STEPS; i++) {
        // Implement gravitational lensing (bend ray towards center)
        let dist_to_center = length(p);
        let pull_str = 0.05 / (dist_to_center * dist_to_center + 0.1);
        rd = normalize(rd - normalize(p) * pull_str * 0.05); // Bend ray

        let map_res = map(p);
        let dS = map_res.x;

        if(dS < SURF_DIST || dO > MAX_DIST) { break; }

        p += rd * dS;
        dO += dS;
    }

    // Shade base on hit normal + iridescence

    return vec4<f32>(col, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (id.x >= dims.x || id.y >= dims.y) { return; }

    let uv = (vec2<f32>(id.xy) - 0.5 * vec2<f32>(dims)) / f32(dims.y);

    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv.x, uv.y, 1.0));

    let color = raymarching(ro, rd);

    textureStore(writeTexture, id.xy, color);
}
```

## Parameters (for UI sliders)
- **Singularity Mass** (0.5, 0.0, 1.0, 0.01)
- **Bismuth Iterations** (5.0, 1.0, 10.0, 1.0)
- **Iridescence Frequency** (2.0, 0.1, 5.0, 0.1)
- **Acoustic Extrusion Force** (1.0, 0.0, 3.0, 0.05)
