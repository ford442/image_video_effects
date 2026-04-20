# Shader Plan: Celestial Forge

## Concept
A massive sci-fi megastructure enclosing a miniature star, functioning as a "Stellar Forge." The scene features a central, pulsating energy core (sun/plasma ball) emitting intense light, surrounded by nested, contra-rotating metallic rings (similar to an armillary sphere or Dyson structure). The rings feature complex surface detailing carved using boolean operations. Plasma arcs occasionally bridge the gap between the rings and the core.

## Metadata
- **Category:** `generative`
- **Tags:** `space`, `megastructure`, `dyson sphere`, `plasma`, `rings`, `sci-fi`, `raymarching`, `3d`

## Features
- **Pulsating Energy Core:** A central sphere that acts as the primary light source and emissive object.
- **Contra-Rotating Rings:** Nested tori that rotate at different speeds and axes, controlled by time and user parameters.
- **Surface Detailing:** Boolean SDF operations used to carve sci-fi greebles and trenches into the rings.
- **Interactive Parameters:** `zoom_params` are mapped to rotation speed, structural complexity, ring scale, and core intensity.
- **Mouse Control:** Implements standard orbit control via `zoom_config.yz`.

## Proposed Code Structure (WGSL)

### Uniforms Definition
Must strictly match the renderer's layout to ensure proper data alignment:
```wgsl
struct Uniforms {
    config: vec4<f32>,       // x: time, y: width, z: height
    zoom_config: vec4<f32>,  // x: zoom, y: mouse_x, z: mouse_y
    zoom_params: vec4<f32>,  // custom params mapped from JSON
}

@group(0) @binding(3) var<uniform> u: Uniforms;
// ... (standard bindings for out_texture, depth, etc.)
```

### Core Functions
- **Rotation Helper:** `fn rot2D(a: f32) -> mat2x2<f32>`
- **Noise/FBM:** Used for plasma texturing.
- **SDFs:** `fn sdSphere(p: vec3<f32>, s: f32) -> f32`, `fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32`, `fn sdCylinder(...)`

### Map Function (`map`)
Evaluates the scene geometry:
- Extracts parameters from `u.zoom_params` (e.g., `speed`, `complexity`).
- Calculates the core distance (`sdSphere`).
- Loops through 3-4 nested rings, rotating the domain `p` differently for each, and calculating `sdTorus`.
- Uses boolean subtract `opS` or `max(a, -b)` for trenches.
- Keeps track of material IDs (core vs. metal vs. glowing panel).

### Main Compute Shader (`main`)
- **Workgroup Size:** `@workgroup_size(8, 8, 1)`
- **Ray Setup:** Calculates normalized device coordinates (NDC) and ray direction (`rd`). Integrates `u.zoom_config.yz` for mouse camera orbit.
- **Raymarching Loop:** Marches along `rd` until a hit or maximum distance.
- **Lighting & Shading:**
  - If hitting metal (rings), calculates normals via finite difference of `map()`.
  - Applies a central point light and rim lighting.
  - Accumulates emission from the core based on proximity to the center and plasma details.
- **Output:** Writes the final color and depth.

## JSON Configuration

```json
{
  "id": "gen-celestial-forge",
  "name": "Celestial Forge",
  "url": "shaders/gen-celestial-forge.wgsl",
  "category": "generative",
  "description": "A massive sci-fi megastructure enclosing a miniature star, featuring contra-rotating rings, plasma arcs, and glowing panels.",
  "tags": ["space", "megastructure", "dyson sphere", "plasma", "rings", "sci-fi", "raymarching", "3d"],
  "features": ["mouse-driven"],
  "params": [
    {
      "id": "param1",
      "name": "Rotation Speed",
      "default": 1.0,
      "min": 0.0,
      "max": 2.0,
      "step": 0.01
    },
    {
      "id": "param2",
      "name": "Complexity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "param3",
      "name": "Ring Scale",
      "default": 1.0,
      "min": 0.5,
      "max": 2.0,
      "step": 0.01
    },
    {
      "id": "param4",
      "name": "Core Intensity",
      "default": 1.0,
      "min": 0.0,
      "max": 5.0,
      "step": 0.01
    }
  ]
}
```