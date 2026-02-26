# New Shader Plan: Quantum Neural Lace

## 1. Concept
**Title:** Quantum Neural Lace
**Description:** A mesmerizing 3D visualization of a hyper-advanced neural interface. It features a crystalline lattice of quantum nodes connected by pulsating, organic fiber-optic strands. The structure floats in a void of digital particulate matter. The aesthetic blends cyberpunk hard-tech with organic fluidity.

## 2. Metadata
- **Category:** `generative`
- **Tags:** `["cyber", "network", "3d", "raymarching", "scifi", "glowing", "lattice"]`
- **Features:** `["raymarched", "mouse-driven"]`

## 3. Features & Controls
- **Mouse Interaction:**
  - `Mouse X`: Rotates the camera view around the lattice.
  - `Mouse Y`: Controls the "system load" - higher Y increases pulse speed and fiber brightness.
- **Parameters (`u.zoom_params`):**
  - `Param 1` (x): **Lattice Density** - Controls the spacing between nodes.
  - `Param 2` (y): **Pulse Frequency** - Speed of the light pulses traveling along fibers.
  - `Param 3` (z): **Fiber Distortion** - Amount of sine-wave "wiggle" in the connecting strands.
  - `Param 4` (w): **Glow Intensity** - Brightness of the node cores and active pulses.

## 4. Proposed Code Structure

### Core Functions
- **`sdOctahedron(p, s)`**: SDF for the quantum nodes.
- **`sdCappedCylinder(p, h, r)`**: SDF for the connecting strands.
- **`opRep(p, c)`**: Domain repetition to create the infinite lattice.
- **`map(p)`**:
  - Apply domain repetition.
  - Place an Octahedron at the center of each cell.
  - Place connected cylinders along X, Y, Z axes.
  - Apply `sin(p.z + time)` displacement to cylinders based on Param 3 to make them look organic.
  - Union (`smin`) the shapes for smooth blending.
- **`main`**:
  - Setup Camera (ray origin/direction) based on Mouse X.
  - Standard Raymarching loop.
  - **Material/Lighting**:
    - "Tech" shading: Blinn-Phong with high specular.
    - Emissive term: based on `sin(length(p) - time * speed)` to simulate data packets moving outwards.
    - Volumetric glow accumulation.

### WGSL Skeleton
```wgsl
struct Uniforms { ... } // Standard struct

// SDF Primitives
fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 { ... }

fn map(p: vec3<f32>) -> vec2<f32> {
    // 1. Domain Repetition
    // 2. Nodes (Octahedrons)
    // 3. Strands (Cylinders with sine wave offset)
    // Return min(dist, material_id)
}

@compute @workgroup_size(8, 8, 1)
fn main(...) {
    // Raymarching logic
    // Lighting with emission pulses
}
```

## 5. JSON Configuration
```json
{
  "id": "gen-quantum-neural-lace",
  "name": "Quantum Neural Lace",
  "url": "shaders/gen-quantum-neural-lace.wgsl",
  "category": "generative",
  "tags": ["cyber", "network", "3d", "raymarching", "scifi"],
  "features": ["raymarched", "mouse-driven"],
  "params": [
    { "id": "density", "name": "Lattice Density", "default": 0.5, "min": 0.1, "max": 1.0 },
    { "id": "speed", "name": "Pulse Speed", "default": 0.5, "min": 0.0, "max": 1.0 },
    { "id": "distortion", "name": "Fiber Chaos", "default": 0.2, "min": 0.0, "max": 0.5 },
    { "id": "glow", "name": "Energy Level", "default": 0.6, "min": 0.0, "max": 1.0 }
  ]
}
```
