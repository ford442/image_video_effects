# New Shader Plan: Gen - Art Deco Skyscraper

## Concept
An infinite vertical ascent through a procedural Art Deco metropolis. The camera moves upwards along the facade of a monumental skyscraper, surrounded by other towers in the distance. The architecture features stepped setbacks, geometric relief patterns, and gold/black marble materials with neon accents.

## Metadata
- **ID:** `gen-art-deco-sky`
- **Name:** Art Deco Skyscraper
- **Category:** `generative`
- **Tags:** `["3d", "raymarching", "architecture", "art-deco", "gold", "scifi", "procedural", "infinite"]`
- **Description:** Infinite vertical ascent up a monumental Art Deco tower with gold fluting and geometric patterns.

## Features
- **Infinite Verticality:** Uses domain repetition on the Y-axis to create an endless tower.
- **Art Deco Styling:** Procedural SDF modeling of fluted columns, sunburst motifs, and stepped geometry.
- **Atmosphere:** Volumetric lighting (shafts), distance fog, and city glow.
- **Interactive Controls:**
  - **Density:** Controls the proximity/number of background towers.
  - **Speed:** Controls the camera's ascent speed.
  - **Glow:** Adjusts the intensity of the gold reflections and neon windows.
  - **Fog:** Controls the atmospheric density.

## Proposed Code Structure

### 1. Header & Uniforms
Standard header with `u.zoom_params` mapping:
- `x`: Building Density (0.0 - 1.0)
- `y`: Ascent Speed (0.0 - 5.0)
- `z`: Glow Intensity (0.0 - 2.0)
- `w`: Fog Density (0.0 - 1.0)

### 2. SDF Functions
- `sdBox`, `sdCappedCylinder`, `sdOctahedron` (for geometric decorations).
- `opRep`: Domain repetition function.
- `opSymX`, `opSymZ`: Symmetry operations for building facades.

### 3. Map Function
- **Main Tower:**
  - Central `sdBox` with symmetry.
  - **Fluting:** Subtractive Sine waves on the surface.
  - **Windows:** Recessed vertical strips with emission material ID.
  - **Gold Trim:** Extruded geometric shapes at regular Y intervals.
- **Background Towers:**
  - Simpler box repetitions in the distance, modulated by `u.zoom_params.x`.

### 4. Rendering (Main)
- **Camera:** Looking slightly up, moving continuously in +Y based on `time * speed`.
- **Raymarching:** Standard loop with `t` accumulation.
- **Materials:**
  - ID 1: Black Marble (Base) - High specular.
  - ID 2: Gold (Trim) - Yellow/Orange reflection.
  - ID 3: Glass (Windows) - Emissive.
- **Lighting:**
  - Directional light (Moon/City Glow).
  - Specular highlights for gold.
  - Fake reflection mapping (env map approximation).

### 5. JSON Configuration
```json
{
  "id": "gen-art-deco-sky",
  "name": "Art Deco Skyscraper",
  "url": "shaders/gen-art-deco-sky.wgsl",
  "category": "generative",
  "description": "Infinite vertical ascent up a monumental Art Deco tower with gold fluting and geometric patterns.",
  "tags": ["3d", "raymarching", "architecture", "art-deco", "gold", "scifi", "procedural", "infinite"],
  "features": ["mouse-driven"],
  "params": [
    {
      "id": "param1",
      "name": "City Density",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "id": "param2",
      "name": "Ascent Speed",
      "default": 1.0,
      "min": 0.0,
      "max": 5.0,
      "step": 0.1
    },
    {
      "id": "param3",
      "name": "Gold Glow",
      "default": 1.0,
      "min": 0.0,
      "max": 2.0,
      "step": 0.1
    },
    {
      "id": "param4",
      "name": "Fog Density",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    }
  ]
}
```
