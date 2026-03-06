# Bismuth Crystal Citadel
## Concept
The "Bismuth Crystal Citadel" is an endlessly generating, raymarched structure resembling the stepped, iridescent hopper crystals characteristic of elemental bismuth. A central pillar ascends infinitely, surrounded by an intricate fractal array of geometric terraces.
The aesthetic leverages sharp orthogonal cuts mapped against thin-film interference coloring (simulated via smooth color ramps indexed by surface normal and stepped gradients) to produce vibrant, shifting metallic hues. The camera rotates and slowly pans through the towering, metallic canyons.

## Metadata
- **Name:** Bismuth Crystal Citadel
- **ID:** gen-bismuth-crystal-citadel
- **Category:** generative
- **Tags:** ["generative", "raymarch", "procedural", "crystal", "bismuth", "metallic", "iridescent", "geometry", "fractal"]
- **Features:** ["raymarched", "mouse-driven"]

## Features
- **Stepped SDF Geometry:** Uses a specialized Distance Function with a `mod` or `floor`/`fract` operation wrapped inside `sdBox` combining to form the characteristic stair-stepped structural decay of bismuth.
- **Domain Repetition:** Uses polar domain repetition (`mod(atan2, ...)`) and height-based domain repetition (`mod(p.y, ...)`) to generate an infinite canyon/pillar topology.
- **Iridescent Shading:** A specialized material function maps lighting incidence angle (Fresnel) and spatial coordinates to an oscillating color palette (via `cos` based color shifts) to mimic thin-film interference.
- **Interactive Lighting:** Mouse coordinates drive the position of a secondary light source illuminating the intricate steps from varied angles, emphasizing the geometry.

## Proposed Code Structure (WGSL)

```wgsl
struct Uniforms {
    resolution: vec2<f32>,
    time: f32,
    mouse: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    config: vec4<f32>,
}

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var output_texture: texture_storage_2d<rgba8unorm, write>;

// Palettes for iridescent metallic look
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Box SDF
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// Map function: Stepped Bismuth Crystal logic
fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;

    // Global twist/rotation
    p.x = p.x * cos(p.y * 0.05) - p.z * sin(p.y * 0.05);
    p.z = p_in.x * sin(p.y * 0.05) + p.z * cos(p.y * 0.05);

    // Infinite vertical repetition
    let spacingY = 4.0;
    p.y = (p.y % spacingY + spacingY) % spacingY - spacingY * 0.5;

    // Polar repetition for citadel structure
    let angle = atan2(p.z, p.x);
    let radius = length(vec2<f32>(p.x, p.z));

    let segments = 6.0;
    let a = (angle + 3.14159) / (6.28318 / segments);
    let a_mod = fract(a) * (6.28318 / segments) - (3.14159 / segments);

    p.x = radius * cos(a_mod);
    p.z = radius * sin(a_mod);

    // Bismuth stepping logic (using mod on domain before sdBox)
    // We create terraced cuts into a larger structure
    let stepSize = u.zoom_params.x * 0.5 + 0.1; // Parameterized step size
    var pStep = p;
    pStep.x = floor(pStep.x / stepSize) * stepSize;
    pStep.z = floor(pStep.z / stepSize) * stepSize;
    pStep.y = floor(pStep.y / stepSize) * stepSize;

    // Combine base geometry and terraced geometry
    let d1 = sdBox(p - vec3<f32>(2.0, 0.0, 0.0), vec3<f32>(1.0, 1.5, 1.0));

    // The "hopper" hollow center effect
    let inner_hollow = sdBox(p - vec3<f32>(2.0, 0.0, 0.0), vec3<f32>(0.8, 1.6, 0.8));

    // Terraced boolean intersection/subtraction
    let d2 = sdBox(p - pStep, vec3<f32>(stepSize * 0.9));

    // Basic approximation of the bismuth form
    var d = max(d1, -inner_hollow);
    d = max(d, d2 - 0.1);

    return d;
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.001;
    return normalize(e.xyy * map(p + e.xyy) +
                     e.yyx * map(p + e.yyx) +
                     e.yxy * map(p + e.yxy) +
                     e.xxx * map(p + e.xxx));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let tex_coords = vec2<i32>(id.xy);
    let resolution = vec2<f32>(u.resolution);

    if (f32(tex_coords.x) >= resolution.x || f32(tex_coords.y) >= resolution.y) {
        return;
    }

    var uv = (vec2<f32>(tex_coords) - 0.5 * resolution) / resolution.y;

    // Camera setup
    let time = u.time * u.zoom_params.y; // Parameterized speed
    var ro = vec3<f32>(0.0, time * 2.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse rotation
    let mouse = u.zoom_config.yz; // (Mouse X, Mouse Y) usually mapped here
    let rotX = rot(mouse.y * 3.14 + 0.2);
    let rotY = rot(mouse.x * 6.28 + time * 0.2);

    rd.y = rd.y * rotX[0][0] + rd.z * rotX[0][1];
    rd.z = rd.y * rotX[1][0] + rd.z * rotX[1][1];

    rd.x = rd.x * rotY[0][0] + rd.z * rotY[0][1];
    rd.z = rd.x * rotY[1][0] + rd.z * rotY[1][1];

    // Raymarching loop
    var t = 0.0;
    var d = 0.0;
    let max_steps = 100;
    let max_dist = 50.0;

    for (var i = 0; i < max_steps; i++) {
        let p = ro + rd * t;
        d = map(p);
        if (d < 0.001 || t > max_dist) { break; }
        t += d * 0.8; // Relax step size for complex terrain
    }

    var col = vec3<f32>(0.02, 0.02, 0.03); // Background

    if (t < max_dist) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Lighting
        let lightPos = vec3<f32>(3.0 * sin(time), ro.y + 4.0, 3.0 * cos(time));
        let l = normalize(lightPos - p);
        let v = normalize(ro - p);

        let diff = max(dot(n, l), 0.0);
        let spec = pow(max(dot(reflect(-l, n), v), 0.0), 32.0);

        // Iridescence (thin-film interference approximation)
        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 5.0);
        let interferenceOffset = p.y * 0.1 + p.x * 0.05;

        // Palette: vibrant bismuth colors (magenta, gold, cyan, blue)
        let c_a = vec3<f32>(0.5, 0.5, 0.5);
        let c_b = vec3<f32>(0.5, 0.5, 0.5);
        let c_c = vec3<f32>(1.0, 1.0, 1.0);
        let c_d = vec3<f32>(0.00, 0.33, 0.67);

        let iridColor = palette(fresnel * u.zoom_params.w + interferenceOffset, c_a, c_b, c_c, c_d);

        // Material composition
        col = iridColor * (diff * 0.8 + 0.2) + spec * u.zoom_params.z;

        // Ambient Occlusion approximation (based on steps)
        let ao = 1.0 - f32(i) / f32(max_steps);
        col *= ao;

        // Fog
        col = mix(col, vec3<f32>(0.02, 0.02, 0.03), 1.0 - exp(-0.02 * t * t));
    }

    // Output
    textureStore(output_texture, tex_coords, vec4<f32>(col, 1.0));
}
```

## JSON Configuration

```json
{
  "id": "gen-bismuth-crystal-citadel",
  "name": "Bismuth Crystal Citadel",
  "url": "shaders/gen-bismuth-crystal-citadel.wgsl",
  "category": "generative",
  "description": "An endless procedural canyon of iridescent, stair-stepped geometric bismuth crystals.",
  "tags": [
    "generative",
    "raymarch",
    "procedural",
    "crystal",
    "bismuth",
    "metallic",
    "iridescent",
    "geometry",
    "fractal"
  ],
  "features": [
    "raymarched",
    "mouse-driven"
  ],
  "author": "Jules",
  "params": [
    {
      "id": "stepSize",
      "name": "Terrace Step Size",
      "default": 0.5,
      "min": 0.1,
      "max": 1.5,
      "step": 0.05
    },
    {
      "id": "speed",
      "name": "Ascension Speed",
      "default": 0.5,
      "min": 0.0,
      "max": 2.0,
      "step": 0.05
    },
    {
      "id": "specular",
      "name": "Metallic Shine",
      "default": 0.8,
      "min": 0.0,
      "max": 2.0,
      "step": 0.05
    },
    {
      "id": "iridescence",
      "name": "Iridescence Shift",
      "default": 1.0,
      "min": 0.0,
      "max": 5.0,
      "step": 0.1
    }
  ]
}
```
