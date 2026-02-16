# New Shader Plan: Cosmic Jellyfish

## Overview
**Shader ID:** `cosmic-jellyfish`
**Name:** Cosmic Jellyfish
**Category:** `generative`
**Tags:** `["3d", "raymarching", "bioluminescent", "space", "organic", "calm"]`

## Description
A single-pass raymarching shader that renders a majestic, translucent jellyfish floating in a cosmic void. The jellyfish features a pulsating bell and undulating tentacles. The scene is illuminated by the jellyfish's own internal bioluminescence and a distant starfield.

## Features
- **Procedural 3D Geometry:** Uses Signed Distance Functions (SDFs) to model the bell (ellipsoid/sphere with modification) and tentacles (sine-distorted cylinders/capsules).
- **Bioluminescence:** The jellyfish core glows, and the tentacles have emissive tips.
- **Dynamic Animation:** The bell expands and contracts rhythmically (breathing). Tentacles wave gently using domain repetition and time-based sine offsets.
- **Cosmic Environment:** A simple procedural starfield background.
- **Interactive Camera:** Mouse movement orbits the camera around the jellyfish.

## Uniforms Mapping
- **`u.config.x` (Time):** Drives the pulsation and tentacle animation.
- **`u.zoom_config.yz` (Mouse):** Controls the camera orbit angles (yaw and pitch).
- **`u.zoom_params.x` (Pulse Speed):** Controls the speed of the jellyfish's breathing cycle.
- **`u.zoom_params.y` (Tentacle Activity):** Controls the amplitude/frequency of the tentacle wave.
- **`u.zoom_params.z` (Hue Shift):** Shifts the base color of the bioluminescence.
- **`u.zoom_params.w` (Glow Intensity):** Controls the brightness of the internal glow and rim lighting.

## Technical Implementation

### Raymarching Strategy
- **SDF Composition:**
    - `sdBell`: A sphere distorted by a cosine function on the bottom to create the bell shape.
    - `sdTentacles`: Several instances of vertical capsules, displaced by sine waves (`p.x += sin(p.y * freq + time)`).
    - `Union`: Smooth union (`smin`) to blend the bell and tentacles organically.
- **Volume/Translucency:**
    - Instead of opaque surface rendering, we can accumulate color along the ray (volumetric rendering) or use a "thick glass" approximation by marching inside the SDF or using the normal for Fresnel effects.
    - Simplified approach for performance: Render the surface, but add an "inner glow" term based on the distance to the core SDF, and mix with a fresnel rim light.

### Proposed Code Structure

```wgsl
// ... standard header ...

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ... noise/hash functions ...

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// SDF for the Jellyfish
fn map(p: vec3<f32>, time: f32) -> f32 {
    // Pulse animation
    let pulse = sin(time * u.zoom_params.x * 2.0) * 0.1;

    // Bell (Ellipsoid-ish)
    var p_bell = p;
    p_bell.y -= 0.5;
    // Stretch
    let d_bell = length(p_bell / vec3<f32>(1.0 + pulse, 0.8 - pulse, 1.0 + pulse)) * 0.8 - 0.5;

    // Hollow out bottom
    let d_hollow = length(p_bell + vec3<f32>(0.0, 0.5, 0.0)) - 0.4;
    let bell_final = max(d_bell, -d_hollow);

    // Tentacles
    var d_tentacles = 100.0;
    // ... loop for tentacles with sine displacement ...

    return min(bell_final, d_tentacles); // or smin
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    // ... resolution, uv, mouse setup ...

    // Camera
    let mouse = u.zoom_config.yz * 2.0 - 1.0;
    var ro = vec3<f32>(0.0, 0.0, -3.0);
    // Rotate camera based on mouse
    ro.yz = rot(mouse.y) * ro.yz;
    ro.xz = rot(mouse.x) * ro.xz;

    let rd = normalize(vec3<f32>(uv, 1.0)); // Need proper camera matrix

    // Raymarch loop
    var t = 0.0;
    var glow = 0.0;
    for(var i=0; i<64; i++) {
        let p = ro + rd * t;
        let d = map(p, u.config.x);

        // Accumulate glow near the surface
        glow += 1.0 / (1.0 + d * d * 20.0);

        if (d < 0.001 || t > 10.0) { break; }
        t += d;
    }

    // Coloring
    var col = vec3<f32>(0.0);
    // Add Starfield background

    if (t < 10.0) {
        // Hit surface - add rim light and base color
        let p = ro + rd * t;
        // let n = calcNormal(p);
        // ... lighting logic ...
    }

    // Add accumulated glow (bioluminescence)
    let glowColor = vec3<f32>(0.1, 0.4, 0.9); // Base Blue
    // Apply Hue Shift (u.zoom_params.z)

    col += glow * glowColor * u.zoom_params.w * 0.05;

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, 1.0));
}
```

## Next Steps
1. Create `public/shaders/cosmic-jellyfish.wgsl` with the implementation.
2. Create `shader_definitions/generative/cosmic-jellyfish.json`.
3. Verify using `scripts/generate_shader_lists.js` and `scripts/check_duplicates.js`.
