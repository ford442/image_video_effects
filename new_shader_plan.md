# New Shader Plan: Fractal Clockwork

## Overview
"Fractal Clockwork" is a 3D generative shader that visualizes an infinite, procedural machine composed of interlocking gears and cogs. The shader uses raymarching with domain repetition to create a vast field of mechanical components that rotate in sync. The aesthetic is "Steampunk/Clockpunk" with metallic materials (brass, gold, steel) and intricate details.

## Features
- **Infinite Gear Field**: Uses modulo arithmetic to repeat gear structures across the XZ plane.
- **Raymarching**: Signed Distance Fields (SDF) define the gear geometry, including teeth and axles.
- **Synchronized Animation**: Gears rotate based on time, with adjacent gears rotating in opposite directions to simulate mechanical meshing.
- **Metallic Shading**: Physically-based rendering approximation for metallic surfaces with specular highlights.
- **Interactive Camera**: Mouse controls the camera orbit and zoom level.
- **Fractal Detail**: Smaller gears are nested or placed in the gaps of larger gears (optional complexity).

## Technical Implementation
- **File**: `public/shaders/gen-fractal-clockwork.wgsl`
- **Category**: `generative`
- **Tags**: `["steampunk", "mechanical", "3d", "raymarching", "gears"]`
- **Algorithm**:
    - **SDF**: A `sdGear` function that combines a cylinder with a radial repetition of teeth (using `atan` and `smoothstep`).
    - **Domain Repetition**: `p.xz = mod(p.xz, spacing) - 0.5 * spacing`.
    - **Checkerboard Rotation**: `((cell_id.x + cell_id.y) % 2.0) * 2.0 - 1.0` determines rotation direction.

## Proposed Code Structure (Draft)

```wgsl
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
// ... (standard bindings)

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// Rotation Matrix
fn rot2D(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Gear SDF
fn sdGear(p: vec3<f32>, radius: f32, teeth: f32, thickness: f32, time: f32) -> f32 {
    // Rotate
    let p_rot = vec3<f32>(rot2D(time) * p.xy, p.z); // Rotate around Z axis if gear is flat on XY?
    // Actually let's assume gear is flat on XZ plane (y is up)

    // Convert to polar
    let r = length(p.xz);
    let a = atan2(p.z, p.x) + time;

    // Teeth
    // Simple sine teeth: radius + sin(a * teeth) * depth
    // Or square teeth
    let tooth_depth = 0.05 * radius;
    let d_teeth = smoothstep(-0.5, 0.5, sin(a * teeth)) * tooth_depth;

    let d_cylinder = r - (radius + d_teeth);
    let d_height = abs(p.y) - thickness;

    // Axle hole
    let d_axle = r - radius * 0.2;

    // Combine
    let gear = max(d_cylinder, d_height);
    return max(gear, -d_axle);
}

// Map Function
fn map(p: vec3<f32>) -> vec2<f32> {
    let spacing = 4.0;
    let cell_id = floor((p.xz + spacing * 0.5) / spacing);
    var q = p;
    q.x = (fract((p.x + spacing * 0.5) / spacing) - 0.5) * spacing;
    q.z = (fract((p.z + spacing * 0.5) / spacing) - 0.5) * spacing;

    // Checkerboard rotation direction
    let direction = ((cell_id.x + cell_id.y) % 2.0) * 2.0 - 1.0;
    let speed = u.zoom_params.z * 2.0 + 0.5;
    let time = u.config.x * speed * direction;

    // Gear params
    let radius = 1.8;
    let teeth = 12.0;
    let thickness = 0.2;

    let d = sdGear(q, radius, teeth, thickness, time);

    // Floor
    let d_floor = p.y + 1.0;

    return vec2<f32>(min(d, d_floor), 1.0);
}

// Raymarch Function
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var t = 0.0;
    for(var i=0; i<100; i++) {
        let p = ro + rd * t;
        let d = map(p).x;
        if(d < 0.001 || t > 100.0) { break; }
        t += d;
    }
    return vec2<f32>(t, 0.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // ... Camera Setup ...
    // ... Rendering Loop ...
    // ... Shading (Metallic) ...
    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}
```

## Parameters
- **Zoom (Params X)**: Scale of the gears / Camera Distance.
- **Teeth (Params Y)**: Number of teeth on gears (complexity).
- **Speed (Params Z)**: Rotation speed.
- **Color/Material (Params W)**: Shift between Gold, Brass, and Steel.

## Integration Steps
1.  **Create Shader**: `public/shaders/gen-fractal-clockwork.wgsl`
2.  **Create Definition**: `shader_definitions/generative/gen-fractal-clockwork.json`
3.  **Run Scripts**: `node scripts/generate_shader_lists.js`
4.  **Verification**: Test in browser.
