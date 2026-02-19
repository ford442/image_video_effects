# New Shader Plan: Generative: Neuro-Cosmos

## Concept
A mesmerizing 3D generative visualization of a "Neuro-Cosmos" — a structure that visually bridges the gap between a biological neural network and the cosmic web of the universe. The scene consists of an infinite, self-repeating 3D web of glowing nodes (neurons/stars) connected by filament-like structures (synapses/dark matter bridges), with pulses of energy traveling through them.

## Metadata
- **ID:** `gen-neuro-cosmos`
- **Name:** Neuro-Cosmos
- **Category:** Generative
- **Tags:** ["network", "neural", "cosmic", "web", "3d", "raymarching", "voronoi", "glowing", "cyber"]

## Features
1.  **Infinite 3D Web:** Uses 3D Cellular Noise (Voronoi) metrics to generate an organic, interconnected lattice structure.
    - `F1` (closest feature point) defines the cell centers (Neurons).
    - `F2 - F1` (difference between second and first closest) defines the cell boundaries (Synaptic Web).
2.  **Dynamic Energy Pulses:** Signals travel along the web strands, simulated by modulating the emission based on time and distance from cell centers.
3.  **Volumetric Glow:** A "fog" accumulation step during raymarching or a post-process glow based on the SDF distance to create a dreamy, ethereal atmosphere.
4.  **Interactive Camera:** Mouse controls the camera orbit (Yaw/Pitch) to explore the structure.
5.  **Interactive Excitation:** Mouse clicks or proximity could trigger "bursts" of activity in the network.

## Parameters (Uniforms)
The shader will utilize the standard `Uniforms` struct:
- `u.config.x` (Time): Drivers the pulse animation and camera drift.
- `u.zoom_config.yz` (Mouse): Controls camera rotation.
- `u.zoom_params`:
    - `x`: **Network Density** (Scales the Voronoi grid).
    - `y`: **Pulse Speed** (Speed of energy signals).
    - `z`: **Glow Intensity** (Brightness of the web and nodes).
    - `w`: **Connection Thickness** (Adjusts the `F2-F1` threshold for web strands).

## Proposed Code Structure

### 1. Hash Function
Standard 3D hash for Voronoi feature point generation.
```wgsl
fn hash33(p: vec3<f32>) -> vec3<f32> {
    let p3 = fract(p * vec3<f32>(.1031, .1030, .0973));
    let p3_mod = p3 + dot(p3, p3.yxz + 33.33);
    return fract((p3_mod.xxy + p3_mod.yxx) * p3_mod.zyx);
}
```

### 2. Voronoi / SDF Logic
Calculate `F1` and `F2` distances to generate the geometry.
```wgsl
fn voronoiMap(p: vec3<f32>) -> vec4<f32> {
    // Returns vec4(d, cell_id_hash, edge_dist, ...)
    // ... implementation of 3x3x3 neighbor search ...
    // Calculate d = min(d, distance(p, neighbor_pos))
    // Keep track of F1 and F2
    // Result:
    // Dist to Neuron Surface = F1 - radius
    // Dist to Synapse = (F2 - F1) - thickness
    // Smooth min to blend them.
}
```

### 3. Raymarching
Standard raymarching loop with:
- `map()` calls.
- Accumulation of "glow" (translucency/additive color) when the ray is close to geometry, to simulate volume.
- Early exit on hit or max distance.

### 4. Coloring
- **Nodes:** Bright white/gold centers fading to blue/purple.
- **Strands:** Darker blue/cyan, lighting up with pulses.
- **Pulse Logic:** `sin(dist_along_strand - time * speed)` to modulate brightness.

## JSON Configuration (`gen-neuro-cosmos.json`)
```json
{
  "name": "Neuro-Cosmos",
  "id": "gen-neuro-cosmos",
  "type": "generative",
  "source": "shaders/gen-neuro-cosmos.wgsl",
  "uniforms": {
    "zoom_params": {
      "x": 1.0,
      "y": 1.0,
      "z": 0.5,
      "w": 0.1
    }
  },
  "tags": ["network", "neural", "cosmic", "3d", "generative"]
}
```
