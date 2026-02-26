# New Shader Plan: Brutalist Monument

## 1. Concept
**Name:** Brutalist Monument
**File ID:** `gen-brutalist-monument`
**Category:** Generative
**Description:** A massive, atmospheric architectural environment inspired by brutalism. Features infinite repeating concrete megastructures and a mysterious floating artifact.
**Visual Style:**
*   **Palette:** Monochrome concrete (light gray to dark gray), contrasted with a single bold color (e.g., gold or black) for the artifact.
*   **Lighting:** Strong directional light (harsh shadows) combined with volumetric fog for depth.
*   **Texture:** Noise-based bump mapping to simulate concrete surface imperfections.
*   **Composition:** Vertical emphasis, towering slabs, monumental scale.

## 2. Metadata
*   **Tags:** `["brutalism", "architecture", "atmospheric", "3d", "raymarching", "monumental"]`
*   **Author:** AI
*   **License:** MIT

## 3. Features
*   **Infinite Procedural Architecture:** Uses domain repetition (`opRep`) to create endless rows of pillars/slabs.
*   **Dynamic Lighting:** Interactive sun position or time-based lighting.
*   **Floating Artifact:** A central geometric object (Sphere, Cube, or Pyramid) that hovers and rotates.
*   **Atmospheric Fog:** Distance-based fog to obscure the horizon and add scale.
*   **Mouse Interaction:** Orbit camera around the artifact or fly through the structures.

## 4. Proposed Code Structure (WGSL)

### Key Functions
*   `sdBox(p: vec3<f32>, b: vec3<f32>) -> f32`: Signed distance function for concrete slabs.
*   `sdSphere(p: vec3<f32>, s: f32) -> f32`: SDF for the artifact.
*   `opRep(p: vec3<f32>, c: vec3<f32>) -> vec3<f32>`: Domain repetition for infinite structures.
*   `map(p: vec3<f32>) -> f32`: Combines the architecture and the artifact.
    *   **Ground:** `p.y + offset`.
    *   **Pillars:** Repeated boxes with height variation based on noise(cell ID).
    *   **Artifact:** Central object with floating animation (`sin(time)`).
*   `calcNormal(p: vec3<f32>) -> vec3<f32>`: Standard gradient-based normal calculation.
*   `raymarch(ro: vec3<f32>, rd: vec3<f32>) -> f32`: Raymarching loop with fixed step count (e.g., 100-200).
*   `shade(p: vec3<f32>, n: vec3<f32>) -> vec3<f32>`: PBR-lite shading.
    *   **Diffuse:** Lambertian.
    *   **Specular:** Blinn-Phong for the artifact (shiny) vs. low spec for concrete (matte).
    *   **AO:** Ambient Occlusion based on SDF steps or dedicated function.
    *   **Fog:** Exponential fog based on distance `t`.

### Uniforms
Standard `Uniforms` struct:
*   `u.config`: Time, Resolution.
*   `u.zoom_config`: Camera control (Mouse X/Y).
*   `u.zoom_params`: Custom parameters.

## 5. JSON Configuration (`shader_definitions/generative/gen-brutalist-monument.json`)

```json
{
  "id": "gen-brutalist-monument",
  "name": "Brutalist Monument",
  "url": "shaders/gen-brutalist-monument.wgsl",
  "category": "generative",
  "description": "Massive concrete architecture in an atmospheric void.",
  "features": ["mouse-driven"],
  "tags": ["brutalism", "architecture", "atmospheric", "3d", "raymarching"],
  "params": [
    {
      "id": "sun_angle",
      "name": "Sun Angle",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "fog_density",
      "name": "Fog Density",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "artifact_scale",
      "name": "Artifact Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "complexity",
      "name": "Structure Complexity",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    }
  ]
}
```
