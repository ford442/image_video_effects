# New Shader Plan: Isometric Cyber-City

## Overview
This shader generates an infinite, procedural cyberpunk city viewed from an isometric perspective. It uses raymarching to render a grid of skyscrapers with varying heights, illuminated by neon windows and street traffic. The effect is purely generative and does not require an input image, though it could optionally use audio or mouse input to modulate the city's activity.

## Features
- **Procedural Architecture**: Buildings are generated on a grid with heights determined by a pseudo-random noise function.
- **Neon Aesthetic**: High-contrast visual style with dark buildings and bright, glowing windows/edges (cyan, magenta, blue).
- **Dynamic Traffic**: Simulated traffic pulses move along the "streets" (gaps between buildings) to add life and motion.
- **Depth & Atmosphere**: Fog is applied based on distance and height to create a sense of scale and depth.
- **Interactive Camera**: The mouse controls the camera's pan position or the speed of the flyover.

## Technical Implementation
- **File**: `public/shaders/gen-isometric-city.wgsl`
- **Type**: Compute Shader
- **Category**: `generative`
- **Algorithm**:
  - **Raymarching**: A `map(pos)` function defines the scene distance. The scene consists of a floor plane and many box primitives (buildings).
  - **Grid Traversal**: Instead of testing every building, the ray can traverse a 2D grid (DDA algorithm) or simply snap the position to the nearest grid cell to determine the building height at that location.
  - **Heightmap**: `height = hash(grid_uv)` determines the building height.
  - **Lighting**: Simple diffuse + emissive. Windows are procedural textures applied to the sides of the boxes.
  - **Fog**: Exponential fog based on ray distance.

## Proposed Code Structure (Draft)

```wgsl
// Constants
const MAX_STEPS = 100;
const MAX_DIST = 100.0;
const SURF_DIST = 0.01;

// Pseudo-random function
fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Distance function for the city
fn map(p: vec3<f32>) -> f32 {
    let q = p;
    // Repeat domain logic here or sample height from hash
    let cell = floor(q.xz);
    let local = fract(q.xz) - 0.5;
    let h = hash(cell) * 5.0; // Building height

    // Box SDF
    let d_building = sdBox(vec3<f32>(local.x, q.y - h * 0.5, local.y), vec3<f32>(0.4, h * 0.5, 0.4));
    let d_floor = p.y;

    return min(d_building, d_floor);
}

// Main render loop
fn render(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    // Raymarching loop...
    // Lighting calculation...
    // Fog application...
}
```

## Parameters
- **Mouse X/Y**: Controls camera pan/angle.
- **Param 1 (Density)**: Controls the density or height variance of the buildings.
- **Param 2 (Speed)**: Controls the speed of the traffic/lights.
- **Param 3 (Glow)**: Controls the intensity of the neon lights.

## Integration Steps
1.  **Create Shader**: `public/shaders/gen-isometric-city.wgsl`.
2.  **Define Properties**: Create `shader_definitions/generative/gen-isometric-city.json` with the appropriate metadata.
3.  **Verify**: Ensure the shader appears in the "Generative" category and renders correctly.
