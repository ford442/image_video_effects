# New Shader Plan: Glacial-Aether Quantum-Cavern

## Overview
An infinitely deep, freezing subterranean cavern of quantum ice that glows with auroral aether-plasma, physically cracking and echoing with kaleidoscopic light refractions upon heavy bass impulses.

## Features
- Volumetric, iridescent ice fractals generated via KIFS (Kaleidoscopic Iterated Function Systems).
- Subsurface auroral scattering that pulses based on mid and high-frequency audio bands.
- Dynamic fracture networks that crack and heal in response to heavy bass transients.
- Zero-gravity plasma mist that flows through the cavern, reacting to mouse interactions.
- Kaleidoscopic chromatic aberration and internal refraction modeling.
- Temporal ping-pong buffers to simulate the slow freezing and melting cycles of the ice.

## Technical Implementation
- File: public/shaders/gen-glacial-aether-quantum-cavern.wgsl
- Category: generative
- Tags: ["fractal", "ice", "quantum", "reactive", "volumetric", "cavern"]
- Algorithm: Raymarching a hyper-dimensional ice-cave SDF using folding space, blended with volumetric plasma density integration.

### Core Algorithm
Raymarching an inverted KIFS (Kaleidoscopic Iterated Function System) fractal for the cavern walls. The SDF uses absolute folding and rotations to create sharp, crystalline ice structures. Volumetric light integration accumulates glowing aether density in the hollow spaces, while ping-pong buffers simulate temporal ice crystallization.

### Mouse Interaction
Mouse coordinates act as a local heat source, melting the ice SDF and stirring the volumetric plasma mist in a swirling vortex based on distance to the cursor.

### Color Mapping / Shading
Glassy, refractive ice shading with subsurface scattering. The plasma is colored using a cool cyan-to-magenta spectral gradient, with bass impacts flashing pure white and cyan, driving the chromatic aberration offset.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Glacial-Aether Quantum-Cavern
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Ice Density, y=Plasma Glow, z=Fracture Rate, w=Cavern Scale
    ripples: array<vec4<f32>, 50>,
};

fn rotate(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn mapSDF(p: vec3<f32>) -> f32 {
    var q = p;
    // Folding space for KIFS
    for (var i = 0; i < 4; i++) {
        q = abs(q) - vec3<f32>(1.0) * u.zoom_params.w; // Cavern Scale
        q.xy = q.xy * rotate(u.config.x * 0.1 + u.config.y * 0.5);
        q.xz = q.xz * rotate(u.config.x * 0.15);
    }
    return length(q) - u.zoom_params.x * 2.0; // Ice Density
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(id.xy) / res;
    var col = vec3<f32>(0.0);

    // Setup camera
    var ro = vec3<f32>(0.0, 0.0, -5.0 + u.config.x);
    var rd = normalize(vec3<f32>(uv * 2.0 - 1.0, 1.0));
    rd.xy = rd.xy * rotate(u.zoom_config.y * 3.14);
    rd.yz = rd.yz * rotate(u.zoom_config.z * 3.14);

    // Raymarching loop
    var t = 0.0;
    var max_dist = 20.0;
    var hit = false;
    for(var i = 0; i < 64; i++) {
        let p = ro + rd * t;
        let d = mapSDF(p);
        if(d < 0.01) { hit = true; break; }
        if(t > max_dist) { break; }
        t += d;
    }

    // Basic Shading
    if (hit) {
        let p = ro + rd * t;
        col = vec3<f32>(0.1, 0.4, 0.8) * (1.0 / (1.0 + t * t * 0.1)) * u.zoom_params.y; // Plasma Glow
    }

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}
```

Parameters (for UI sliders)

Name (default, min, max, step)
Ice Density (0.5, 0.1, 1.0, 0.01)
Plasma Glow (0.8, 0.0, 2.0, 0.01)
Fracture Rate (0.2, 0.0, 1.0, 0.01)
Cavern Scale (1.5, 0.5, 3.0, 0.05)

Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-05-20_glacial-aether-quantum-cavern.md" "Glacial-Aether Quantum-Cavern"
