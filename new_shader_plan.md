# New Shader Plan: Hyper Labyrinth

## Overview
"Hyper Labyrinth" is a generative 3D shader that visualizes a 4D maze structure. By rotating the 4D maze and taking a 3D slice (the visible world), the walls of the labyrinth appear to morph, shift, and reconfigure themselves seamlessly over time. The aesthetic is "Neon/Cyber" with glowing path markers and a dark, reflective atmosphere.

## Features
- **4D Geometry**: The maze is generated in 4D space. Time drives the rotation in the 4th dimension, causing the 3D cross-section to evolve.
- **Raymarching**: Uses signed distance fields (SDF) to render the geometry.
- **Neon Aesthetics**: The maze walls are dark, while the grid floors and path centers emit a neon glow (cyan/magenta).
- **Interactive Camera**: The mouse controls the camera's viewing angle (orbit or fly-through).
- **Dynamic Complexity**: User parameters control the scale of the maze and the speed of the 4D morphing.

## Technical Implementation
- **File**: `public/shaders/gen-hyper-labyrinth.wgsl`
- **Category**: `generative`
- **Algorithm**:
    - **SDF**: A grid-based SDF using trigonometric functions or modular arithmetic to define walls.
    - **4D Rotation**: A rotation matrix involving the W-axis is applied to the input coordinate before the SDF evaluation.
    - **Lighting**: Standard Phong shading combined with an emissive component derived from the SDF (e.g., proximity to the center of a corridor).

## Proposed Code Structure (Draft)

```wgsl
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
// ... (other bindings)

struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// 4D Rotation
fn rotate4D(p: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    // Rotate in XW plane
    return vec4<f32>(
        p.x * c - p.w * s,
        p.y,
        p.z,
        p.x * s + p.w * c
    );
}

// Map function (SDF)
fn map(pos3: vec3<f32>) -> vec2<f32> {
    // 1. Transform 3D pos to 4D (w depends on time or constant)
    var p4 = vec4<f32>(pos3, 1.0);

    // 2. Apply 4D rotation driven by time/params
    let speed = mix(0.1, 2.0, u.zoom_params.y);
    p4 = rotate4D(p4, u.config.x * speed);

    // 3. Maze generation logic (e.g., Gyroid or Grid)
    // Gyroid: sin(x)cos(y) + sin(y)cos(z) + sin(z)cos(x) = 0
    // 4D Gyroid: sin(x)cos(y) + sin(y)cos(z) + sin(z)cos(w) + sin(w)cos(x)

    let scale = mix(1.0, 5.0, u.zoom_params.x);
    let q = p4 * scale;

    let val = sin(q.x)*cos(q.y) + sin(q.y)*cos(q.z) + sin(q.z)*cos(q.w) + sin(q.w)*cos(q.x);

    // Thickness threshold
    let thickness = mix(0.1, 1.0, u.zoom_params.w); // Wall thickness
    let d = abs(val) - thickness * 0.5;

    // Scale distance back
    return vec2<f32>(d * 0.5 / scale, 1.0); // 1.0 = material ID
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    // Standard raymarching loop
    var t = 0.0;
    for(var i=0; i<100; i++) {
        let p = ro + rd * t;
        let d = map(p).x;
        if(d < 0.001 || t > 50.0) { break; }
        t += d;
    }
    return vec2<f32>(t, 0.0); // Material ID handling needed
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // ... setup UVs and Camera ...

    // Mouse interaction for Camera Angle
    let mouse = u.zoom_config.yz;
    // ...

    // Render
    let t = raymarch(ro, rd).x;

    // Shading
    var color = vec3<f32>(0.0);
    if(t < 50.0) {
        let p = ro + rd * t;
        // Calculate Normal
        // ...

        // Coloring based on 4D coordinate or normal
        color = vec3<f32>(0.1, 0.8, 0.9); // Base Cyan

        // Add glow based on proximity to gyroid center
        let glow = 1.0 / (1.0 + t * t * 0.1);
        color += vec3<f32>(1.0, 0.2, 0.8) * glow; // Magenta glow
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));
}
```

## Parameters
- **Mouse**: Orbit Camera.
- **Param 1 (Scale)**: Zoom/Density of the maze.
- **Param 2 (Morph)**: Speed of the 4D rotation.
- **Param 3 (Glow)**: Intensity of the neon glow.
- **Param 4 (Thickness)**: Thickness of the maze walls.

## Integration Steps
1.  **Create Shader**: `public/shaders/gen-hyper-labyrinth.wgsl`
2.  **Create Definition**: `shader_definitions/generative/gen-hyper-labyrinth.json`
3.  **Validation**: Verify compilation and effect in the "Generative" category.
