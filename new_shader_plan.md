# Shader Plan: Retro-wave Horizon

## Concept
A retro-futuristic landscape featuring an infinite neon wireframe grid terrain that scrolls towards the viewer, with a glowing digital sun on the horizon, towering synthwave mountains in the distance, and an atmospheric outrun sky.

## Metadata
- **Category:** generative
- **Tags:** `["synthwave", "retro", "neon", "grid", "80s", "raymarching"]`

## Features
- Infinite scrolling wireframe terrain using plane SDF and grid patterns based on modulo arithmetic.
- Large, pulsating synthetic sun with characteristic horizontal 'blinds' or scanline cuts.
- Background mountain range using simple heightmapping and FBM.
- Parameters mapped to `u.zoom_params` to control scroll speed, grid glow intensity, sun size/position, and color theme shift.
- Mouse interaction via `u.zoom_config.yz` to pan the camera horizontally and vertically.

## Proposed Code Structure (WGSL)

```wgsl
struct Uniforms {
    config: vec4<f32>,       // x: time, y: aspect, z: unused, w: unused
    zoom_config: vec4<f32>,  // x: zoom, y: mouse_x, z: mouse_y, w: unused
    zoom_params: vec4<f32>,  // x: speed, y: glow, z: sun_size, w: color_shift
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var output_texture: texture_storage_2d<bgra8unorm, write>;

// SDF functions and noise
fn sdPlane(p: vec3<f32>, n: vec3<f32>, h: f32) -> f32 {
    return dot(p, n) + h;
}

fn map(p: vec3<f32>) -> f32 {
    let speed = u.zoom_params.x * 2.0;
    let time = u.config.x * speed;

    var pos = p;
    pos.z -= time; // Scrolling effect

    // Base plane
    let planeDist = sdPlane(pos, vec3<f32>(0.0, 1.0, 0.0), 1.0);

    // Add simple mountains/hills using sine waves and FBM
    // ...
    return planeDist;
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let tex_coords = vec2<i32>(id.xy);
    let dimensions = textureDimensions(output_texture);

    if (tex_coords.x >= dimensions.x || tex_coords.y >= dimensions.y) {
        return;
    }

    let resolution = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    let uv = (vec2<f32>(tex_coords) - 0.5 * resolution) / resolution.y;

    let time = u.config.x;

    // Camera setup with mouse interaction
    let mouse = u.zoom_config.yz;
    let ro = vec3<f32>(mouse.x * 5.0, 1.0 + mouse.y * 2.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching
    var t = 0.0;
    var p = ro;
    for(var i = 0; i < 100; i++) {
        p = ro + rd * t;
        let d = map(p);
        if(d < 0.001 || t > 100.0) { break; }
        t += d;
    }

    // Rendering logic (grid lines, horizon sun, mountains)
    var col = vec3<f32>(0.0);

    // Sky/Sun logic if ray missed terrain
    if (t > 100.0) {
        // Render retro sun and background
    } else {
        // Render neon grid terrain
    }

    textureStore(output_texture, tex_coords, vec4<f32>(col, 1.0));
}
```

## JSON Configuration

```json
{
  "id": "gen-retrowave-horizon",
  "name": "Retro-wave Horizon",
  "url": "shaders/gen-retrowave-horizon.wgsl",
  "category": "generative",
  "description": "An infinite neon wireframe landscape with a glowing sun on the horizon, in classic outrun style.",
  "features": ["mouse-driven"],
  "tags": ["synthwave", "retro", "neon", "grid", "80s", "raymarching"],
  "params": [
    {
      "id": "speed",
      "name": "Scroll Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "grid_glow",
      "name": "Grid Glow",
      "default": 0.7,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "sun_size",
      "name": "Sun Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "color_shift",
      "name": "Color Shift",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    }
  ]
}
```
