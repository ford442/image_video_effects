# New Shader Plan: Celestial Clockwork Plasma-Loom

## Overview
A gargantuan interstellar loom of turning astrolabes and celestial gears forged from liquid plasma and starlight, weaving threads of radiant energy across an endless, deep-void chronosphere. It merges ornate, mechanical clockwork structures with ethereal, fluid cosmology, shining in rich cosmic indigo, starfire gold, and searing solar orange.

## Features
- **Interlocking Astrolabe Gears:** Nested spherical SDF geometries intricately cut into orbital rings and clockwork cogs that rotate independently around a central singularity.
- **Plasma Thread Weaving:** Audio-reactive, hyper-luminescent fluid threads that snake between the gears, their thickness and intensity driven by low-frequency pulses.
- **Fractal Chronosphere Void:** A background domain of repeating, time-warped geometric constellations simulating an infinite starry ether.
- **Volumetric Starfire Accents:** Intense, bloom-heavy emissions along the edges of the gears that mimic coronal mass ejections.
- **Glass-Metallic Refraction:** The gears themselves act as partially transparent, heavily refractive chronoglass, distorting the cosmic threads behind them.
- **Pulsing Singularity Core:** A central, microscopic black hole surrounded by a bright accretion disk that aggressively pulses with sub-bass audio inputs.

## Technical Implementation
- File: public/shaders/gen-celestial-clockwork-plasma-loom.wgsl
- Category: generative
- Tags: ["mechanical", "cosmic", "plasma", "clockwork", "fractal", "audio-reactive"]
- Algorithm: Raymarching nested boolean SDF operations (subtractions and intersections) with multi-axis rotational matrices, fluid simulation overlays, and heavy volumetric bloom.

### Core Algorithm
The foundational geometry consists of multiple concentric spheres and tori, dynamically subtracted using polar repetition to form gear teeth and intricate latticework. The entire coordinate space undergoes continuous rotational transformations across the X, Y, and Z axes (`p = rot(time * speed) * p`), simulating complex clockwork mechanisms. The plasma threads are generated using 3D Simplex noise extruded along curved splines interpolating between the gears. Audio reactivity (`plasmaBuffer[0].x`) modulates both the rotational speed of the inner rings and the displacement amplitude of the plasma noise.

### Mouse Interaction
The mouse (`u.zoom_config.yz`) shifts the rotational origin and acts as a localized time-dilation field. When moving the cursor, the local coordinate space twists (`p.xy = rot(mouse_dist * strength) * p.xy`), causing the clockwork gears to momentarily warp and the plasma threads to aggressively bend toward the singularity point defined by the mouse coordinates.

### Color Mapping / Shading
A sophisticated physically-based approximation using a deep indigo base for the chronoglass. Refraction is faked by offset sampling the background fractal void based on surface normals. Emissive shading is driven by a color palette of intense gold and solar orange, heavily scaled by `plasmaBuffer` inputs. A multi-pass raymarching approach accumulates energy density for the volumetric plasma threads, producing a rich, soft-glow bloom effect.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Celestial Clockwork Plasma-Loom
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

// ... Constants, 3D Noise, and Rotation Functions ...

// Function to rotate a point
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Map function for the clockwork gears and plasma threads
fn map(p: vec3<f32>) -> f32 {
    // Nested torus and sphere SDFs
    // Polar repetition for gear teeth
    // Audio displacement from plasmaBuffer
    return 1.0;
}

// Raymarching, normal calculation, and shading
fn render(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(0.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) GlobalInvocationID: vec3<u32>) {
    let uv = vec2<f32>(GlobalInvocationID.xy) / u.zoom_config.xy; // Base resolution proxy
    // ... setup camera, raymarch loop, accumulate color, bloom pass
    textureStore(writeTexture, vec2<i32>(GlobalInvocationID.xy), vec4<f32>(uv, 0.5, 1.0));
}
```

## Parameters (for UI sliders)
- `zoom_params.x`: Gear Complexity and Count (default: 0.5, min: 0.0, max: 1.0, step: 0.01)
- `zoom_params.y`: Audio Plasma Reactivity (default: 0.5, min: 0.0, max: 1.0, step: 0.01)
- `zoom_params.z`: Loom Rotation Speed (default: 0.5, min: 0.0, max: 1.0, step: 0.01)
- `zoom_params.w`: Time Dilation Intensity (default: 0.5, min: 0.0, max: 1.0, step: 0.01)
