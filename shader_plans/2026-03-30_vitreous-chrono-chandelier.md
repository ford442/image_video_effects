# New Shader Plan: Vitreous Chrono-Chandelier

## Overview
An infinite, abyssal cavern illuminated by a colossal, self-assembling chandelier of hyper-refractive glass chimes and glowing quantum pendulums that shatter and reform to the rhythm of time and sound.

## Features
- Infinite cascading arrays of refractive glass stalactites and geometric chimes.
- Subsurface scattering and internal chromatic dispersion within the glass elements.
- Audio-reactive shattering and crystalline reformation of the chandelier structures.
- Swinging quantum pendulums with motion trails driven by domain-warped noise.
- A glowing volumetric atmospheric fog that reacts to deep bass frequencies.
- Interactive gravity wells that allow the user's mouse to swing the pendulums.
- Dynamic color shifts across the chromatic spectrum based on time dilation.

## Technical Implementation
- File: public/shaders/gen-vitreous-chrono-chandelier.wgsl
- Category: generative
- Tags: ["crystal", "mechanical", "audio-reactive", "raymarching", "glass"]
- Algorithm: Raymarching with heavily instanced (domain-repeated) geometric primitives, KIFS folding for the chimes, and complex refractive transmission approximations.

### Core Algorithm
Utilizes raymarching with global domain repetition along the X and Z axes, with exponential scaling along the Y axis to create a descending cavernous feel. The chimes are generated using a blend of `sdCylinder` and `sdOctahedron` with KIFS (Kaleidoscopic Iterated Function System) folding. Audio data (`u.config.y`, `u.config.z`, `u.config.w`) directly manipulates the KIFS angles and the domain spacing.

### Mouse Interaction
The mouse acts as a localized repulsor/attractor in 3D space. Using distance from the camera ray to a projected mouse coordinate, the glass pendulums bend away or swing towards the cursor via an inverse-square distortion matrix applied to the space before evaluating the SDF.

### Color Mapping / Shading
Uses a thin-film interference model coupled with Schlick's approximation for Fresnel. Background light leaks through the "glass" via simulated chromatic aberration, separating RGB rays during the raymarch accumulation step. The chimes glow from within with neon teal, magenta, and gold, blooming heavily when audio bass peaks.

## Proposed Code Structure (WGSL)
```wgsl
// ----------------------------------------------------------------
// Vitreous Chrono-Chandelier
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
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Shatter Threshold, y=Chime Density, z=Refraction Index, w=Glow Intensity
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let p_abs = abs(p);
    return (p_abs.x + p_abs.y + p_abs.z - s) * 0.57735027;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    let uv = (fragCoord * 2.0 - res) / res.y;

    // Parameters mapped from zoom_params
    let shatterThreshold = u.zoom_params.x;
    let chimeDensity = u.zoom_params.y;
    let refractionIndex = u.zoom_params.z;
    let glowIntensity = u.zoom_params.w;

    // Audio Reactivity
    let audioBass = u.config.y;
    let time = u.config.x * 0.5;

    // Camera setup
    var ro = vec3<f32>(0.0, 5.0, -10.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse Interaction
    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * res.x / res.y;
    let mouseY = -(u.zoom_config.z * 2.0 - 1.0);
    let mousePos = vec3<f32>(mouseX * 5.0, 5.0 + mouseY * 5.0, 0.0);

    // Raymarching Loop
    var t = 0.0;
    var col = vec3<f32>(0.0);
    var glow = vec3<f32>(0.0);

    for(var i=0; i<100; i++) {
        var p = ro + rd * t;

        // Apply mouse distortion / swinging pendulums
        let distToMouse = distance(p, mousePos);
        if (distToMouse < 4.0) {
            p += normalize(p - mousePos) * (1.0 / (distToMouse + 0.5)) * audioBass;
        }

        // Domain Repetition for Chandelier Lattice
        var q = p;
        q.x = q.x - round(q.x / chimeDensity) * chimeDensity;
        q.z = q.z - round(q.z / chimeDensity) * chimeDensity;

        let d = sdOctahedron(q, 1.0); // Simplified SDF

        if (d < 0.001) {
            // Material properties and Refraction
            col = vec3<f32>(0.1, 0.5, 0.9) * glowIntensity;
            break;
        }

        glow += vec3<f32>(0.8, 0.2, 0.9) * 0.005 / (abs(d) + 0.05) * audioBass;
        t += d * 0.6;
        if(t > 50.0) { break; }
    }

    col += glow;
    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
```

## UI Parameters
### Parameters (for UI sliders)

Name (default, min, max, step)
- Shatter Threshold (0.5, 0.0, 1.0, 0.01)
- Chime Density (4.0, 1.0, 10.0, 0.1)
- Refraction Index (1.3, 1.0, 2.5, 0.01)
- Glow Intensity (1.0, 0.0, 3.0, 0.05)

## Integration Steps

Create shader file
Create JSON definition
Run generate_shader_lists.js
Upload via storage_manager

After creating the file, add it to the queue by running:
python scripts/manage_queue.py add "2026-03-30_vitreous-chrono-chandelier.md" "Vitreous Chrono-Chandelier"
Reply with only: "✅ Plan created and queued: 2026-03-30_vitreous-chrono-chandelier.md"
