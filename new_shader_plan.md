# New Shader Plan: Biomechanical Hive

## Concept
An infinite, claustrophobic structure composed of hexagonal cells that blur the line between industrial machinery and organic tissue. The walls are ribbed with metallic piping that seems to breathe, and the centers of the cells glow with a pulsating, embryonic light. The scene evokes the aesthetic of H.R. Giger—alien, dark, and intricately detailed.

## Metadata
- **Name:** `gen-biomechanical-hive.wgsl`
- **Category:** `generative`
- **Tags:** `["scifi", "biomechanical", "giger", "alien", "raymarching", "horror"]`
- **Author:** Jules

## Features
- **Hexagonal Tiling:** Uses domain repetition with modulo arithmetic to create an infinite honeycomb structure.
- **Organic/Industrial Blend:** SDFs combining sharp geometric forms (pipes, hex prisms) with smooth blending (`smin`) and noise-based displacement to simulate fleshy overgrowth.
- **Pulsating Atmosphere:** The lighting intensity and color shift rhythmically, simulating a heartbeat or breathing.
- **Interactive Camera:** Mouse controls the camera angle to inspect the details of the hive.

## Uniforms Mapping
| Uniform | Parameter | Description |
| :--- | :--- | :--- |
| `u.zoom_params.x` | **Cell Density** | Controls the scale of the hexagonal grid (zoom level). |
| `u.zoom_params.y` | **Pulse Speed** | Speed of the rhythmic lighting and wall breathing. |
| `u.zoom_params.z` | **Biomass** | Amount of "organic" noise/displacement applied to the structure. |
| `u.zoom_params.w` | **Hue Shift** | Shifts the core color (e.g., from Amber to Alien Green or Bloody Red). |
| `u.zoom_config.yz` | **Camera** | Mouse X/Y maps to camera Yaw/Pitch. |

## Proposed Code Structure (WGSL)

### Header
Standard bindings and `Uniforms` struct.

### Helper Functions
- `sdHexPrism(p: vec3<f32>, h: vec2<f32>) -> f32`: Signed distance for hexagonal cells.
- `opRepLim(p: vec3<f32>, c: f32, l: vec3<f32>) -> vec3<f32>`: Limited domain repetition (or infinite `mod`).
- `smin(a: f32, b: f32, k: f32) -> f32`: Smooth minimum for organic blending.

### Map Function
```wgsl
fn map(p: vec3<f32>) -> vec2<f32> {
    // 1. Domain Repetition (Hexagonal Grid)
    // Convert to hex coordinates for tiling
    let size = mix(4.0, 1.5, u.zoom_params.x);
    let q = p;
    // ... Hex grid logic (staggered rows) ...

    // 2. Base Geometry
    // The wall structure
    let d_hex = sdHexPrism(local_p, vec2(size * 0.4, 10.0)) - 0.2;

    // 3. Details (Pipes/Ribs)
    let d_pipes = length(vec2(local_p.x, local_p.z % 0.5)) - 0.05;

    // 4. Organic Displacement
    let breathing = sin(u.config.x * u.zoom_params.y) * 0.1;
    let noise = fbm(p * 0.5 + u.config.x * 0.1);
    let d_organic = d_hex + noise * u.zoom_params.z + breathing;

    // 5. Smooth Blend
    let d = smin(d_organic, d_pipes, 0.5);

    // Material ID based on position (Core vs Wall)
    let mat = select(1.0, 2.0, length(local_p.xy) < size * 0.2); // 2.0 = Glowing Core

    return vec2(d, mat);
}
```

### Lighting & Rendering
- **Lighting Model:** Phong with strong specular for the "slime" look.
- **Volumetric Fog:** Dark fog to hide the distance and add mood.
- **Emissive:** Inner core glows brightly based on the pulse.

## JSON Configuration
```json
{
  "name": "Biomechanical Hive",
  "label": "Hive",
  "uniforms": {
    "zoom_params": {
      "x": 0.5,
      "y": 0.5,
      "z": 0.3,
      "w": 0.0
    }
  },
  "tags": ["scifi", "alien", "generative"]
}
```
