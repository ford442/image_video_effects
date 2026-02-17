# New Shader Plan: Fractal Clockwork

## Concept

**Title**: Fractal Clockwork
**ID**: `gen-fractal-clockwork`
**Category**: `generative`
**Tags**: `steampunk`, `mechanical`, `gears`, `fractal`, `raymarching`, `3d`, `metal`

**Description**:
An infinite, procedurally generated field of interlocking gears and clockwork mechanisms. The camera flies through this dense, 3D mechanical world. The gears rotate in synchronization, driven by a global time variable and mouse interaction. The aesthetic combines industrial metallic textures with subtle magical glows.

## Features

1.  **Infinite Gear Field**: Utilizes domain repetition (modulo arithmetic) to create an endless grid of gears along the X and Z axes.
2.  **Synchronized Rotation**: Gears in adjacent grid cells rotate in alternating directions (checkerboard pattern) to simulate perfect mechanical meshing.
3.  **Procedural Geometry**: Signed Distance Functions (SDFs) define the gear shapes, including teeth, spokes, and central axels.
4.  **Metallic Material**: A specialized shader to simulate brushed metal with specular highlights and environment reflections.
5.  **Mouse Interaction**:
    *   **Mouse X**: Controls the global rotation speed and camera yaw.
    *   **Mouse Y**: Controls the camera pitch or zoom level.

## Proposed Code Structure (Draft WGSL)

```wgsl
// Uniforms structure
struct Uniforms {
    config: vec4<f32>,       // time, resolution
    zoom_config: vec4<f32>,  // mouse.x, mouse.y, unused, unused
    zoom_params: vec4<f32>,  // custom params: density, speed, metallic, glow
};

// Gear SDF
fn gearSDF(p: vec3<f32>, teeth: f32, radius: f32, width: f32) -> f32 {
    // Basic cylinder
    let d_cyl = length(p.xz) - radius;

    // Teeth modulation
    let angle = atan2(p.z, p.x);
    let d_teeth = sin(angle * teeth) * 0.1; // Modulate radius

    // Combine
    let d_final = d_cyl + d_teeth;

    // Cap height
    let d_cap = abs(p.y) - width;

    return max(d_final, d_cap);
}

// Scene Map function using Domain Repetition
fn map(p: vec3<f32>, time: f32) -> f32 {
    let cell_size = 4.0;

    // Domain repetition
    let cell_id = floor(p.xz / cell_size);
    let local_p = vec3<f32>(
        (fract(p.x / cell_size) - 0.5) * cell_size,
        p.y,
        (fract(p.z / cell_size) - 0.5) * cell_size
    );

    // Alternate rotation direction based on cell parity
    let parity = (cell_id.x + cell_id.y) % 2.0;
    let rotation_dir = select(1.0, -1.0, parity > 0.5);

    // Apply rotation
    let rot_angle = time * rotation_dir;
    let c = cos(rot_angle);
    let s = sin(rot_angle);
    let rotated_p = vec3<f32>(
        local_p.x * c - local_p.z * s,
        local_p.y,
        local_p.x * s + local_p.z * c
    );

    return gearSDF(rotated_p, 12.0, 1.5, 0.2);
}

// Main Raymarching Loop
fn main(...) {
    // Setup Ray Origin (ro) and Ray Direction (rd) based on camera/mouse
    // Loop for raymarching map(p)
    // Calculate Normal
    // Apply Lighting (diffuse + specular + metallic reflection)
    // Add Glow based on proximity
    // Output color
}
```

## JSON Configuration

Target file: `shader_definitions/generative/gen-fractal-clockwork.json`

```json
{
  "id": "gen-fractal-clockwork",
  "name": "Fractal Clockwork",
  "url": "shaders/gen-fractal-clockwork.wgsl",
  "category": "generative",
  "description": "An infinite, procedurally generated field of interlocking gears and clockwork mechanisms.",
  "tags": ["steampunk", "mechanical", "gears", "fractal", "raymarching", "3d", "metal"],
  "features": ["mouse-driven"],
  "params": [
    {
      "id": "param1",
      "name": "Gear Density",
      "default": 1.0,
      "min": 0.5,
      "max": 2.0,
      "step": 0.1
    },
    {
      "id": "param2",
      "name": "Rotation Speed",
      "default": 1.0,
      "min": 0.0,
      "max": 5.0,
      "step": 0.1
    },
    {
      "id": "param3",
      "name": "Metallic Shine",
      "default": 0.8,
      "min": 0.0,
      "max": 1.0,
      "step": 0.05
    },
    {
      "id": "param4",
      "name": "Glow Intensity",
      "default": 0.5,
      "min": 0.0,
      "max": 2.0,
      "step": 0.1
    }
  ]
}
```
