# New Shader Plan: Crystal Caverns

## Concept
"Crystal Caverns" is a 3D generative shader that creates an infinite, procedurally generated cave system filled with glowing, jagged crystals. The shader uses raymarching to render the rocky terrain and the translucent crystals, with dynamic lighting effects to simulate bioluminescence and refraction. The user can navigate through the caverns, and adjust parameters to change the density, color, and glow of the crystals.

## Metadata
- **ID**: `gen-crystal-caverns`
- **Name**: Crystal Caverns
- **Category**: `generative`
- **Tags**: `["crystal", "cave", "3d", "raymarching", "generative", "fantasy", "glowing"]`
- **Description**: An infinite, procedural cave system illuminated by clusters of glowing crystals.

## Features
- **Infinite Terrain**: Uses FBM noise and domain repetition to create endless cave structures.
- **Translucent Crystals**: Rendered with a custom material shader that approximates refraction and internal reflection.
- **Dynamic Lighting**: Point lights emanate from the crystals, illuminating the surrounding rock.
- **Mouse Interaction**: Mouse movement controls the camera view (pitch/yaw) or the position of a "lantern" light.
- **Parameters**: Adjustable crystal density, color palette, glow intensity, and cave scale.

## Proposed Code Structure (WGSL)

### Header
Standard shader header with uniforms and texture bindings.

### Helper Functions
- `rotate2D(p: vec2<f32>, angle: f32) -> vec2<f32>`: Rotates a 2D vector.
- `fbm(p: vec3<f32>) -> f32`: Fractal Brownian Motion for terrain noise.
- `sdOctahedron(p: vec3<f32>, s: f32) -> f32`: Signed Distance Function for an octahedron (crystal shape).
- `sdBox(p: vec3<f32>, b: vec3<f32>) -> f32`: SDF for a box (alternative crystal shape).
- `opUnion(d1: f32, d2: f32) -> f32`: Union of two SDFs.
- `opSmoothUnion(d1: f32, d2: f32, k: f32) -> f32`: Smooth union for organic blending.
- `opSubtraction(d1: f32, d2: f32) -> f32`: Subtraction for carving caves.

### Map Function
`fn map(p: vec3<f32>) -> vec2<f32>`
- **Terrain**: Generate a large-scale noise field (`fbm`) to define the cave walls. Use `abs(p.y) - height` or similar to create floor/ceiling, perturbed by noise.
- **Crystals**: Use domain repetition (`mod`) to place crystals at regular intervals on the floor and ceiling. Vary their size and rotation based on position hash.
- **Combination**: Combine terrain and crystals using `min`. Return `vec2(distance, material_id)`. Material ID 1.0 for rock, 2.0 for crystal.

### Raymarching Loop
`fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32>`
- Standard raymarching loop with a max distance and epsilon.
- Accumulate glow/fog based on distance to crystals (optional optimization).

### Shading
`fn render(ro: vec3<f32>, rd: vec3<f32>, t: f32, m: f32) -> vec3<f32>`
- Calculate normal `n`.
- **Rock Material (m=1.0)**:
    - Diffuse lighting from crystal positions (approximated).
    - Specular highlights (wet rock look).
    - Ambient occlusion.
- **Crystal Material (m=2.0)**:
    - Emissive color (glow).
    - Specular highlights (sharp).
    - Fake refraction/transmission (modify normal based on view angle).
    - Rim lighting.
- **Fog**: Distance-based exponential fog to fade to black/background color.

### Main Function
- Setup camera based on `u.config` (time) and `u.zoom_config` (mouse).
- Calculate ray direction `rd`.
- Call `raymarch`.
- Call `render`.
- Apply post-processing (gamma correction, vignetting).

## JSON Configuration

```json
{
  "id": "gen-crystal-caverns",
  "name": "Crystal Caverns",
  "url": "shaders/gen-crystal-caverns.wgsl",
  "category": "generative",
  "description": "An infinite, procedural cave system illuminated by clusters of glowing crystals.",
  "tags": ["crystal", "cave", "3d", "raymarching", "generative", "fantasy", "glowing"],
  "features": ["mouse-driven"],
  "params": [
    {
      "id": "param1",
      "name": "Crystal Density",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "param2",
      "name": "Color Shift",
      "default": 0.0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    },
    {
      "id": "param3",
      "name": "Glow Intensity",
      "default": 0.8,
      "min": 0.0,
      "max": 2.0,
      "step": 0.1
    },
    {
      "id": "param4",
      "name": "Cave Scale",
      "default": 0.5,
      "min": 0.1,
      "max": 2.0,
      "step": 0.1
    }
  ]
}
```
