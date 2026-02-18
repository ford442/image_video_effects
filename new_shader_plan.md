# New Shader Plan: Alien Flora

## Concept

**Title**: Alien Flora
**ID**: `gen-alien-flora`
**Category**: `generative`
**Tags**: `nature`, `plants`, `bioluminescent`, `raymarching`, `3d`, `organic`, `forest`

**Description**:
An infinite, procedurally generated landscape populated by bioluminescent alien vegetation. The scene features rolling hills, glowing mushroom-like structures, and swaying organic forms. The atmosphere is thick with fog and floating spores, creating a mysterious, otherworldly ambiance.

## Features

1.  **Infinite Terrain**: A raymarched ground plane modulated by noise to create rolling hills and valleys.
2.  **Procedural Vegetation**:
    *   **Glowing Mushrooms**: Constructed using Signed Distance Functions (SDFs) for caps and stems, seamlessly blended.
    *   **Swaying Motion**: Vertex displacement applied to the SDFs to simulate wind or underwater currents.
3.  **Atmospheric Effects**:
    *   **Distance Fog**: Fades distant objects into the background color to simulate depth and scale.
    *   **Volumetric Glow**: Accumulates glow from the bioluminescent parts of the plants.
4.  **Mouse Interaction**:
    *   **Mouse X**: Rotates the camera view around the scene (Yaw).
    *   **Mouse Y**: Adjusts the camera height or pitch, allowing views from ground level or above the canopy.

## Proposed Code Structure (Draft WGSL)

```wgsl
// Uniforms structure
struct Uniforms {
    config: vec4<f32>,       // time, aspect, resX, resY
    zoom_config: vec4<f32>,  // mouseX, mouseY, unused, unused
    zoom_params: vec4<f32>,  // density, swaySpeed, glowIntensity, colorShift
};

// SDF Primitives
fn sdSphere(p: vec3<f32>, s: f32) -> f32 { ... }
fn sdCappedCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 { ... }

// Smooth Min for organic blending
fn smin(a: f32, b: f32, k: f32) -> f32 { ... }

// Scene Map
fn map(p: vec3<f32>) -> vec2<f32> {
    // 1. Terrain
    let terrainHeight = sin(p.x * 0.1) * sin(p.z * 0.1) * 2.0;
    let d_terrain = p.y - terrainHeight;

    // 2. Vegetation (Domain Repetition)
    let cell_size = 8.0;
    let id = floor(p.xz / cell_size);
    let q = vec3<f32>(
        (fract(p.x / cell_size) - 0.5) * cell_size,
        p.y - terrainHeight, // Plant grows from ground
        (fract(p.z / cell_size) - 0.5) * cell_size
    );

    // Randomize per cell
    let rand = fract(sin(dot(id, vec2<f32>(12.9898, 78.233))) * 43758.5453);

    // Mushroom SDF
    // Swaying
    let sway = sin(u.config.x * u.zoom_params.y + p.y) * 0.2;
    let stem = sdCappedCylinder(q + vec3<f32>(sway, -2.0, 0.0), 2.0, 0.3 + rand * 0.2);
    let cap = sdSphere(q + vec3<f32>(sway, -4.0 - rand, 0.0), 1.5 + rand);
    let d_plant = smin(stem, cap, 0.5);

    // Combine
    let d = min(d_terrain, d_plant);
    return vec2<f32>(d, 1.0); // 1.0 = material ID
}

// Main Raymarching Loop
fn main(...) {
    // Camera Setup based on Mouse
    // Raymarch loop
    // Lighting (Dark ambient + point lights from glowing caps)
    // Fog application
    // Output
}
```

## JSON Configuration

Target file: `shader_definitions/generative/gen-alien-flora.json`

```json
{
  "id": "gen-alien-flora",
  "name": "Alien Flora",
  "url": "shaders/gen-alien-flora.wgsl",
  "category": "generative",
  "description": "An infinite procedural forest of bioluminescent alien vegetation with swaying mushrooms and atmospheric fog.",
  "tags": ["nature", "plants", "bioluminescent", "raymarching", "3d", "organic", "forest"],
  "features": ["mouse-driven"],
  "params": [
    {
      "id": "param1",
      "name": "Vegetation Density", // Maps to zoom_params.x (Note: domain repetition size is fixed in code, maybe modulate visible plants)
      "default": 1.0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "id": "param2",
      "name": "Sway Speed", // Maps to zoom_params.y
      "default": 1.0,
      "min": 0.0,
      "max": 5.0,
      "step": 0.1
    },
    {
      "id": "param3",
      "name": "Glow Intensity", // Maps to zoom_params.z
      "default": 1.5,
      "min": 0.5,
      "max": 3.0,
      "step": 0.1
    },
    {
      "id": "param4",
      "name": "Color Shift", // Maps to zoom_params.w
      "default": 0.0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.05
    }
  ]
}
```
