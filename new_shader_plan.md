# Biomechanical Hive - New Generative Shader Plan

## Concept
A dark, atmospheric, and infinite 3D tunnel structure inspired by H.R. Giger's biomechanical art. The scene blends organic, fleshy curves with cold, industrial metallic components. The tunnel "breathes" with a slow, pulsating rhythm, and cables or veins intertwine along the walls. The viewer moves constantly forward through this alien architecture.

## Metadata
- **ID:** `gen-biomechanical-hive`
- **Name:** Biomechanical Hive
- **Category:** Generative
- **Tags:** ["3d", "raymarching", "sci-fi", "horror", "organic", "metallic", "tunnel", "dark"]

## Features
- **Infinite Tunnel:** Uses domain repetition (modulo arithmetic) to create an endless corridor.
- **Organic/Industrial Blend:** Smooth blending (`smin`) combines rigid geometric shapes (ribs, pipes) with organic noise displacement.
- **Atmospheric Lighting:** Dark fog fades distant structures into blackness. High specular highlights simulate wet, slimy surfaces.
- **Pulse Animation:** The entire structure subtly expands and contracts, simulating breathing.
- **Interactive Camera:** Mouse position controls the camera's looking direction (yaw/pitch) while movement is automatic forward.

## Proposed Code Structure (WGSL)

### Uniforms
Standard `Uniforms` struct.
- `u.zoom_config.yz`: Mouse X/Y for camera look.
- `u.time`: Animation driver.
- `u.zoom_params`:
    - `x`: Pulse Speed / Breathing Rate
    - `y`: Structural Complexity (Noise scale/amount)
    - `z`: Metallic Shine (Specular intensity)
    - `w`: Fog Density

### Helper Functions
- `sdSphere`, `sdTorus`, `sdCylinder`: Basic primitives.
- `smin(a, b, k)`: Polynomial smooth minimum for blending shapes organically.
- `rot2D(angle)`: 2D rotation matrix for twisting the tunnel.

### Map Function
```wgsl
fn map(p: vec3<f32>) -> f32 {
    // 1. Domain Repetition for infinite tunnel
    let period = 4.0;
    let cell_z = floor(p.z / period);
    let z = (fract(p.z / period) - 0.5) * period; // centered z in cell
    let q = vec3<f32>(p.x, p.y, z);

    // 2. Base Tunnel Shape (Cylinder)
    let tunnel_radius = 3.0 + sin(p.z * 0.5 + u.time * u.zoom_params.x) * 0.2; // Breathing
    let tunnel = -(length(q.xy) - tunnel_radius); // Inside cylinder

    // 3. Ribs (Torus segments)
    // Repeat ribs every period
    let rib_radius = tunnel_radius - 0.2;
    let rib_thickness = 0.3;
    let ribs = sdTorus(q, vec2<f32>(rib_radius, rib_thickness));

    // 4. Cables / Veins (Twisted cylinders along walls)
    let cable_angle = atan2(q.y, q.x) * 3.0 + p.z * 0.5;
    let cable_dist = length(q.xy) - (tunnel_radius - 0.5 + sin(cable_angle) * 0.2);

    // 5. Combine with smooth blend
    var d = smin(tunnel, ribs, 0.5);
    d = smin(d, cable_dist, 0.3);

    // 6. Detail Noise (Texture)
    let noise = sin(p.x * 5.0) * sin(p.y * 5.0) * sin(p.z * 5.0) * 0.05 * u.zoom_params.y;

    return d + noise;
}
```

### Main Rendering Loop (Raymarching)
- Ray origin moves forward: `ro = vec3(0.0, 0.0, u.time * 2.0)`.
- Ray direction `rd` is rotated by mouse input.
- Standard raymarching loop (max steps ~64-128, epsilon 0.001).
- Compute normal using finite differences.
- Lighting:
    - **Ambient:** Dark blue/grey.
    - **Diffuse:** Directional light from "headlamp".
    - **Specular:** High intensity, sharp falloff for "wet" look (controlled by param Z).
- Apply fog based on distance `t`.

## JSON Configuration (`shader_definitions/generative/gen-biomechanical-hive.json`)
```json
{
  "id": "gen-biomechanical-hive",
  "name": "Biomechanical Hive",
  "url": "shaders/gen-biomechanical-hive.wgsl",
  "category": "generative",
  "description": "An infinite, breathing biomechanical tunnel blending organic curves with industrial structure. Features wet metallic surfaces and atmospheric depth.",
  "tags": ["3d", "raymarching", "sci-fi", "horror", "organic", "metallic", "tunnel", "dark"],
  "features": ["mouse-driven"],
  "params": [
    {
      "id": "param1",
      "name": "Pulse Speed",
      "default": 1.0,
      "min": 0.0,
      "max": 5.0,
      "step": 0.1
    },
    {
      "id": "param2",
      "name": "Complexity",
      "default": 1.0,
      "min": 0.0,
      "max": 2.0,
      "step": 0.1
    },
    {
      "id": "param3",
      "name": "Wetness / Shine",
      "default": 0.8,
      "min": 0.0,
      "max": 1.0,
      "step": 0.05
    },
    {
      "id": "param4",
      "name": "Fog Density",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.05
    }
  ]
}
```
