# New Shader Plan: Bioluminescent Abyss

## Concept
An infinite, deep underwater landscape populated by swaying tube worms and thermal vents. The scene is dark, lit primarily by the glowing tips of the flora and faint overhead caustics. This shader aims to capture the serene yet alien atmosphere of the deep ocean.

## Metadata
- **Name:** `gen-bioluminescent-abyss.wgsl`
- **Category:** `generative`
- **Tags:** `["underwater", "organic", "bioluminescence", "raymarching", "volumetric"]`
- **Author:** Jules

## Features
- **Infinite Terrain:** Procedural seabed using FBM noise.
- **Dynamic Flora:** swaying tube worms that react to "current" (time).
- **Atmosphere:** Deep blue exponential fog and fake caustic projections.
- **Interactive:** Mouse controls camera orbit; sliders control density, current, and glow.

## Uniforms Mapping
| Uniform | Parameter | Description |
| :--- | :--- | :--- |
| `u.zoom_params.x` | **Density** | Controls the spacing/count of the tube worms. |
| `u.zoom_params.y` | **Current** | Controls the speed and amplitude of the swaying motion. |
| `u.zoom_params.z` | **Glow** | Intensity of the bioluminescent tips. |
| `u.zoom_params.w` | **Color** | Shift the hue of the bioluminescence (Cyan -> Magenta -> Green). |
| `u.zoom_config.yz` | **Camera** | Mouse X/Y maps to camera Yaw/Pitch. |

## Proposed Code Structure (WGSL)

### Header
Standard include of bindings and Uniforms struct.

### SDF Primitives
- `sdCappedCylinder`: For tube worms.
- `sdCone`: For thermal vents.
- `smin`: Smooth minimum for blending base of worms with terrain.

### Map Function
```wgsl
fn map(p: vec3<f32>) -> vec2<f32> {
    // 1. Terrain
    let d_floor = p.y + 2.0 + fbm(p.xz * 0.1) * 1.0;

    // 2. Tube Worms (Domain Repetition)
    let cell_size = mix(8.0, 2.0, u.zoom_params.x); // Density control
    let id = floor(p.xz / cell_size);
    let q = (fract(p.xz / cell_size) - 0.5) * cell_size;

    // Randomize height and sway offset based on ID
    let h = hash(id);

    // Swaying Logic
    let sway = sin(u.config.x * u.zoom_params.y + h * 10.0) * (q.y * 0.1);
    let p_worm = vec3(q.x + sway, p.y, q.y);

    let d_worm = sdCappedCylinder(p_worm, 2.0 + h, 0.1);

    // Material ID: 1.0 = Floor, 2.0 = Worm Body, 3.0 = Glowing Tip

    // Logic to distinguish tip from body (simple height check)
    var mat = 1.0;
    if (d_worm < d_floor) {
        mat = select(2.0, 3.0, p_worm.y > (2.0 + h - 0.2));
    }

    return vec2(min(d_floor, d_worm), mat);
}
```

### Lighting & Rendering
- **Base Color:** Dark grey/blue for rock/worms.
- **Emissive:** If `mat == 3.0`, add bright color based on `zoom_params.w`.
- **Fog:** `mix(finalColor, deepBlue, 1.0 - exp(-t * 0.05))`
- **Caustics:** Project a domain-warped noise texture from world coordinates onto objects.

## JSON Configuration
```json
{
  "name": "Bioluminescent Abyss",
  "label": "Bio Abyss",
  "uniforms": {
    "zoom_params": {
      "x": 0.5,
      "y": 0.5,
      "z": 0.8,
      "w": 0.0
    }
  },
  "tags": ["underwater", "generative", "3d"]
}
```
