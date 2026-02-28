# New Shader Plan: Gen - Holographic Data Core

## Concept
An infinite fly-through of a quantum computer's holographic data core. The camera glides through a 3D lattice of glowing data cubes, interconnected by pulsing fiber-optic neon circuits. The environment feels both structured and chaotic, representing the flow of raw digital information.

## Metadata
- **ID:** `gen-holographic-data-core`
- **Name:** Holographic Data Core
- **Category:** `generative`
- **Tags:** `["3d", "raymarching", "cyberpunk", "hologram", "data", "neon", "procedural", "infinite"]`
- **Description:** An infinite journey through a quantum lattice of glowing data nodes and pulsing circuits.

## Features
- **Infinite Grid Lattice:** Uses domain repetition (`opRep`) on all three axes (X, Y, Z) to create an endless network of data nodes.
- **Glowing Data Blocks:** Procedural SDF modeling (`sdBox`) for the primary data clusters.
- **Neon Circuit Pathways:** Thin cylinders (`sdCylinder`) connecting the data blocks, emitting light.
- **Pulsing Energy:** Time-based sine waves applied to the emissive materials to simulate data flow.
- **Interactive Controls:**
  - **Node Density:** Controls the spacing between data clusters.
  - **Travel Speed:** Controls the camera's forward movement speed through the Z-axis.
  - **Data Pulse Rate:** Adjusts the speed of the glowing energy pulses.
  - **Holographic Glitch:** Introduces noise and chromatic aberration to the scene.

## Proposed Code Structure

### 1. Header & Uniforms
Standard header with `u.zoom_params` mapping:
- `x`: Node Density (0.1 - 2.0)
- `y`: Travel Speed (0.0 - 10.0)
- `z`: Pulse Rate (0.1 - 5.0)
- `w`: Glitch Intensity (0.0 - 1.0)

### 2. SDF Functions
- `sdBox` (for data nodes).
- `sdCylinder` (for circuit connections).
- `opRep`: Domain repetition function (3D).
- `opSmoothUnion`: Smooth blending function for organic-looking connections.

### 3. Map Function
- **Data Nodes:**
  - `sdBox` repeated using `opRep` with spacing based on `u.zoom_params.x`.
  - Add structural details like inner floating cores using subtractive or additive smaller boxes.
- **Circuits:**
  - Orthogonal `sdCylinder` grids connecting the nodes.
- **Materials:**
  - Assign distinct material IDs for nodes and circuits to control their glow properties independently.

### 4. Rendering (Main)
- **Camera:** Looking forward (+Z), moving continuously based on `time * travel_speed`. Add slight subtle rotation or wobble.
- **Raymarching:** Standard loop with distance accumulation. Add glitch displacements to the ray origin or direction based on `u.zoom_params.w`.
- **Lighting & Materials:**
  - No traditional diffuse lighting. Entirely emissive.
  - Apply colors based on position and time: Cyan/Blue for base structures, Magenta/Orange for active data pulses.
  - Accumulate glow along the ray to create a volumetric, holographic bloom effect.
- **Post-Processing:** Apply a scanline or subtle chromatic aberration effect in the final color output.

### 5. JSON Configuration
```json
{
  "id": "gen-holographic-data-core",
  "name": "Holographic Data Core",
  "url": "shaders/gen-holographic-data-core.wgsl",
  "category": "generative",
  "description": "An infinite journey through a quantum lattice of glowing data nodes and pulsing circuits.",
  "tags": ["3d", "raymarching", "cyberpunk", "hologram", "data", "neon", "procedural", "infinite"],
  "features": ["mouse-driven"],
  "params": [
    {
      "id": "param1",
      "name": "Node Density",
      "default": 1.0,
      "min": 0.1,
      "max": 2.0,
      "step": 0.1
    },
    {
      "id": "param2",
      "name": "Travel Speed",
      "default": 2.0,
      "min": 0.0,
      "max": 10.0,
      "step": 0.5
    },
    {
      "id": "param3",
      "name": "Data Pulse Rate",
      "default": 1.0,
      "min": 0.1,
      "max": 5.0,
      "step": 0.1
    },
    {
      "id": "param4",
      "name": "Glitch Intensity",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0,
      "step": 0.05
    }
  ]
}
```
