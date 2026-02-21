# New Shader Plan: Micro-Cosmos

## 1. Concept
**Shader Name**: Micro-Cosmos
**ID**: `gen-micro-cosmos`
**Category**: Generative
**Description**: A generative simulation of microscopic life forms drifting in a fluid medium. Features translucent, gooey cell membranes, internal organelles, and floating particulate matter (marine snow), all rendered with raymarching and fake subsurface scattering.

## 2. Visual Style
-   **Environment**: Deep blue/cyan/purple fluid background with vignettes, creating a sense of depth and immersion.
-   **Entities**: Soft, glowing, translucent entities (amoebas, paramecia) with varying sizes and shapes. Some contain smaller, denser spheres (organelles).
-   **Motion**: Organic, fluid motion. Entities wobble and drift slowly, influenced by simulated currents and Brownian motion.
-   **Lighting**: Rim lighting (Fresnel) to emphasize the translucent membranes. Inner glow (emission) for organelles. Soft shadows and absorption (Beer's Law approximation) to simulate fluid density.
-   **Depth of Field**: Blur effect for distant objects to enhance the microscopic scale.

## 3. Technical Implementation (WGSL)

### SDF Primitives
-   `sdEllipsoid(p, r)`: Base shape for cells.
-   `sdSphere(p, s)`: Organelles.
-   **Displacement**: `d += sin(p.x * 10.0 + time) * 0.1` applied to the base shape to create wobbling membranes.
-   `smin(d1, d2, k)`: Smooth minimum function to blend cells together softly, mimicking fluid tension and cell fusion/division.

### Domain Repetition
-   Infinite grid using `mod` (or `fract`) on `p.xz` (or `p.xyz`).
-   Random offsets per cell using `hash(id)` to break uniformity in position, size, and rotation.
-   Use `zoom_params.x` (Population Density) to control the grid size or probability of spawning a cell.

### Movement Logic
-   `p.y += time * speed`: Vertical drift.
-   `p.xz += flow * time`: Horizontal drift.
-   `rotate2D` based on time and random seed for tumbling motion.
-   **Mouse Interaction**: Mouse position (`u.zoom_config.yz`) acts as an attractor or repulsor point, modifying the flow field or density near the cursor.

### Lighting Model
-   **Rim Light**: `pow(1.0 - dot(n, -rd), 3.0)` for membrane edges.
-   **Translucency**: Fake SSS by blending background color with object color based on thickness (SDF distance).
-   **Absorption**: Darken color based on distance `t` (fog).

### Uniforms Mapping
-   `u.zoom_params.x`: **Population Density** (0.0 - 1.0) -> Controls grid cell size or spawn probability.
-   `u.zoom_params.y`: **Fluid Viscosity/Speed** (0.0 - 1.0) -> Controls drift speed and wobble frequency.
-   `u.zoom_params.z`: **Membrane Glow** (0.0 - 1.0) -> Controls the intensity of the rim light and emission.
-   `u.zoom_params.w`: **Color Shift** (0.0 - 1.0) -> Shifts the hue of the environment and organisms.
-   `u.zoom_config.yz`: **Mouse Interaction** (Attract/Repel).

## 4. JSON Configuration Draft (`shader_definitions/generative/gen-micro-cosmos.json`)
```json
{
  "id": "gen-micro-cosmos",
  "name": "Micro-Cosmos",
  "url": "shaders/gen-micro-cosmos.wgsl",
  "category": "generative",
  "description": "A microscopic view of a teeming liquid universe, filled with procedural microorganisms, drifting particles, and organic structures.",
  "tags": ["biological", "organic", "microscopic", "liquid", "life", "floating", "generative"],
  "features": ["mouse-driven"],
  "params": [
    {
      "id": "param1",
      "name": "Population Density",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.1
    },
    {
      "id": "param2",
      "name": "Fluid Activity",
      "default": 0.3,
      "min": 0.0,
      "max": 2.0,
      "step": 0.1
    },
    {
      "id": "param3",
      "name": "Membrane Glow",
      "default": 1.0,
      "min": 0.0,
      "max": 3.0,
      "step": 0.1
    },
    {
      "id": "param4",
      "name": "Color Shift",
      "default": 0.0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.05
    }
  ]
}
```

## 5. Implementation Steps
1.  **File Creation**: Create `shader_definitions/generative/gen-micro-cosmos.json` with the JSON content above.
2.  **WGSL Skeleton**: Create `public/shaders/gen-micro-cosmos.wgsl` using the standard header from `gen-alien-flora.wgsl`.
3.  **SDF Implementation**: Write the `map` function with `sdEllipsoid`, `sdSphere`, and domain repetition logic.
4.  **Raymarching Loop**: Implement the standard raymarching loop.
5.  **Lighting & Color**: Implement the custom lighting model for translucency and rim light.
6.  **Integration**: Run `node scripts/generate_shader_lists.js` to register the new shader.
7.  **Verification**: Test in browser (or via `CI=true npm test` for basic checks).
