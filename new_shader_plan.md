# Plan for Gen Chronos Labyrinth Shader

## Concept
An infinite, constantly shifting, impossible M.C. Escher-like maze of floating geometric staircases and corridors that dynamically rotate and assemble themselves in real-time. Glowing temporal rifts periodically open and close within the structure.

## Metadata
* **ID:** `gen-chronos-labyrinth`
* **Name:** Chronos Labyrinth
* **Category:** generative
* **Description:** An infinite, Escher-esque maze of shifting geometric staircases and corridors suspended over a void, with glowing temporal anomalies.
* **Tags:** 3d, raymarching, geometry, escher, maze, impossible, abstract, infinite
* **Features:** mouse-driven

## Parameters (Mapped to `u.zoom_params`)
1. **Labyrinth Complexity** (`zoom_params.x`): Modifies the density and scale of the geometric structures (stairs/blocks).
2. **Shift Speed** (`zoom_params.y`): Controls how fast the paths and blocks rotate or slide into new configurations.
3. **Temporal Rifts** (`zoom_params.z`): Controls the frequency and intensity of the glowing energy rifts appearing in the labyrinth.
4. **Architectural Material** (`zoom_params.w`): Blends between different structural materials (e.g., ancient stone, polished obsidian, neon-lined wireframe).

## Proposed Code Structure (WGSL)

```wgsl
// Standard header
...

struct Uniforms { ... }

// SDF Primitives
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 { ... }
fn sdStaircase(p: vec3<f32>, steps: f32) -> f32 { ... } // Composed of repeated boxes or exact SDF

// Helper Functions
fn rot(a: f32) -> mat2x2<f32> { ... }
fn opRep(p: vec3<f32>, c: vec3<f32>) -> vec3<f32> { ... } // Domain repetition

// Map function
fn map(p: vec3<f32>) -> vec2<f32> {
    // 1. Base domain repetition for infinite space (x, y, z)
    // 2. Parity logic to determine orientation (e.g., stairs going up vs sideways) based on cell index
    // 3. Time-based rotation of individual cells to create shifting illusion
    // 4. Glowing anomalies (spheres or tori) injected at random cell centers
    // Return distance and material ID
}

// Rendering
@compute @workgroup_size(8, 8, 1)
fn main(...) {
    // 1. Ray setup with mouse orbit control
    // 2. Raymarching loop with dynamic geometry
    // 3. Lighting: Directional lights to enhance the structural shapes, ambient occlusion
    // 4. Materials: Procedural textures based on world position and `Architectural Material` param
    // 5. Glow accumulation for the temporal rifts
    // 6. Volumetric fog in the void background
}
```

## JSON Configuration (`shader_definitions/generative/gen-chronos-labyrinth.json`)
```json
{
  "id": "gen-chronos-labyrinth",
  "name": "Chronos Labyrinth",
  "url": "shaders/gen-chronos-labyrinth.wgsl",
  "category": "generative",
  "description": "An infinite, Escher-esque maze of shifting geometric staircases and corridors suspended over a void.",
  "tags": [
    "3d",
    "raymarching",
    "geometry",
    "escher",
    "maze",
    "impossible",
    "abstract",
    "infinite"
  ],
  "features": [
    "mouse-driven"
  ],
  "params": [
    {
      "id": "complexity",
      "name": "Labyrinth Complexity",
      "default": 1.0,
      "min": 0.5,
      "max": 3.0,
      "step": 0.1
    },
    {
      "id": "shift_speed",
      "name": "Shift Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 2.0,
      "step": 0.05
    },
    {
      "id": "rifts",
      "name": "Temporal Rifts",
      "default": 0.8,
      "min": 0.0,
      "max": 2.0,
      "step": 0.1
    },
    {
      "id": "material",
      "name": "Architectural Style",
      "default": 0.0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "description": "0=Ancient Stone, 1=Obsidian & Neon"
    }
  ]
}
```
