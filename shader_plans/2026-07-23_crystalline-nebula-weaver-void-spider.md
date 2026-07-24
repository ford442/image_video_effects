# New Shader Plan: Crystalline Nebula-Weaver Void-Spider

## Overview
A hyper-majestic, biomechanical celestial spider forged from shattered chrono-crystals and liquid auroral plasma, silently weaving a colossal, violently decaying volumetric web across a multi-dimensional quantum rift.

## Features
- Intricate, multi-legged biomechanical arachnid constructed from sharp, crystalline SDFs and smooth plasma-fluid surfaces.
- A vast, glowing, geometric web that spans the void, pulsing with audio-reactive bioluminescent energy that travels along its threads.
- Multi-dimensional volumetric background featuring a violently shifting quantum rift and deep-matter nebulas.
- Fluid-dynamic, liquid auroral plasma coursing through the spider's joints and abdomen, reacting to acoustic sub-bass frequencies.
- Geometric temporal fractals carved into the void as the spider moves and spins its chrono-web.
- High-intensity bioluminescent bloom and chromatic dispersion across the spider's crystalline exoskeleton.

## Technical Implementation
- File: public/shaders/gen-crystalline-nebula-weaver-void-spider.wgsl
- Category: generative
- Tags: ["spider", "crystal", "plasma", "web", "quantum", "void", "audio-reactive"]
- Algorithm: Raymarching combined with domain repetition, fractal noise, and volumetric fluid simulation for the nebula and web threads.

### Core Algorithm
The spider's body is composed of a complex hierarchy of SDFs (capsules, octahedrons, and smooth minimum combinations) representing its segmented exoskeleton and legs. The web is generated using a combination of polar domain repetition and fractal noise, creating a network of glowing threads. The volumetric background is a deep dark-matter nebula rendered with fBM (Fractional Brownian Motion) and raymarching over multiple steps. The temporal web weaving is simulated using time-based displacement and acoustic reactivity driven by `plasmaBuffer[0].x`.

### Mouse Interaction
Mouse movement (extracted via `let mouse = u.zoom_config.yz;`) acts as a gravitational center that distorts the web. The formula offsets the raymarching coordinates in 3D space: `map(p - vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0))`, causing the spider and its web to seemingly orbit and stretch towards the cursor's focal point.

### Color Mapping / Shading
The shader employs deep abyssal purples and blacks for the void, contrasted with radiant neon cyan and magenta for the liquid auroral plasma. The spider's crystalline exoskeleton uses a chromatic dispersion gradient (refracting based on view angle and normal), enhanced with high-intensity bloom and subsurface scattering to give it a hyper-organic glowing appearance. Audio reactivity intensifies the emissive properties of the web nodes and the spider's abdomen.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Crystalline Nebula-Weaver Void-Spider
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>
}

// ----------------------------------------------------------------
// Core SDF and Noise Functions
// ----------------------------------------------------------------

fn fbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var freq = 1.0;
    var pos = p;
    for (var i = 0; i < 5; i++) {
        // Simplified noise logic
        value += amplitude * sin(dot(pos, vec3<f32>(1.0, 1.5, 2.0)));
        pos *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// ----------------------------------------------------------------
// Spider Geometry
// ----------------------------------------------------------------

fn sdSpider(p: vec3<f32>, audioReact: f32) -> f32 {
    // Abdomen and Cephalothorax
    let abdomen = length(p * vec3<f32>(1.0, 1.5, 1.0)) - (1.0 + audioReact * 0.2);
    let head = length(p - vec3<f32>(0.0, 0.0, 1.5)) - 0.7;
    var body = smin(abdomen, head, 0.5);

    // Legs (Simplified Domain Repetition)
    var pLeg = p;
    pLeg.x = abs(pLeg.x) - 1.5;
    let leg = length(max(abs(pLeg) - vec3<f32>(0.2, 2.0, 0.2), vec3<f32>(0.0))) - 0.1;

    return smin(body, leg, 0.2);
}

// ----------------------------------------------------------------
// Web and Environment Geometry
// ----------------------------------------------------------------

fn sdWeb(p: vec3<f32>) -> f32 {
    let thread1 = length(p.xy) - 0.02;
    let thread2 = length(fract(p * 2.0) - 0.5) - 0.01;
    return min(thread1, thread2);
}

fn map(p: vec3<f32>, time: f32, audioReact: f32, mouse: vec2<f32>) -> f32 {
    let displacedP = p - vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0);
    let spider = sdSpider(displacedP, audioReact);
    let web = sdWeb(displacedP) + fbm(p) * 0.1;
    return min(spider, web);
}

// ----------------------------------------------------------------
// Main Raymarching and Shading
// ----------------------------------------------------------------

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    let id = vec2<f32>(f32(global_id.x), f32(global_id.y));
    let uv = (id - 0.5 * vec2<f32>(f32(dimensions.x), f32(dimensions.y))) / f32(dimensions.y);

    let time = u.config.x;
    let audioBass = u.ripples[0].x; // Using plasmaBuffer[0].x proxy
    let mouse = u.zoom_config.yz;

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching loop
    var t = 0.0;
    var d = 0.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        d = map(p, time, audioBass, mouse);
        if (d < 0.001 || t > 20.0) { break; }
        t += d;
    }

    // Basic shading
    var col = vec3<f32>(0.0);
    if (t < 20.0) {
        col = vec3<f32>(0.2, 0.8, 1.0) * (1.0 - t / 20.0);
        col += vec3<f32>(1.0, 0.2, 0.8) * audioBass;
    }

    textureStore(writeTexture, vec2<i32>(i32(global_id.x), i32(global_id.y)), vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)

Web Complexity (1.0, 0.1, 5.0, 0.1)
Gravity Distortion (0.5, 0.0, 2.0, 0.05)
Plasma Intensity (0.8, 0.0, 2.0, 0.05)
Void Depth (1.5, 0.1, 4.0, 0.1)
