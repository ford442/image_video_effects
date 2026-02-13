# New Generative Shader: Cosmic Web Filament

## Concept
A procedural generative shader that simulates the large-scale structure of the universe—the "Cosmic Web." It visualizes filaments of dark matter connecting galaxy clusters, with vast cosmic voids in between. The structure evolves slowly over time, drifting through space.

## Visual Style
- **Primary Structure:** Bright, thin filaments forming a complex, interconnected web.
- **Nodes/Clusters:** Brighter intersections where filaments meet (galaxy clusters).
- **Background:** Deep, dark voids (purple/black) with subtle nebulous gas.
- **Palette:** Cyan/White for high-density matter, Deep Purple/Blue for gas/voids.
- **Motion:** Slow drift and organic warping.
- **Interaction:** The mouse cursor acts as a massive gravity well, pulling the entire web structure towards it (domain distortion).

## Technical Implementation

### Core Algorithm
- **3D Cellular Noise (Voronoi/Worley):** Used to generate the base structure.
- **Filament Metric:** Calculate `F2 - F1` (distance to 2nd closest point minus distance to 1st closest point).
  - High values (where `F1` is small) represent cell centers (voids).
  - Low values (where `F1 ≈ F2`) represent cell boundaries (filaments).
  - Inverting this value (`1.0 / (F2 - F1 + epsilon)`) creates bright lines at the boundaries.
- **Domain Warping:** Apply FBM noise to the input coordinates before sampling the Voronoi noise to distort the straight lines into organic, flowing curves.
- **Density Accumulation:** Raymarch or sample multiple layers of noise to build up density.

### Mouse Interaction
- **Gravity Well:** Calculate vector from current pixel to mouse position.
- **Distortion:** Apply a non-linear displacement to the UV coordinates based on distance to mouse (stronger near mouse, falling off with distance).
- **Formula:** `uv -= normalize(uv - mouse) * strength * smoothstep(radius, 0.0, dist)`

### Color Mapping
- Map the accumulated density to a color gradient.
- **Low Density:** Black/Deep Blue.
- **Medium Density:** Purple/Magenta.
- **High Density:** Cyan/White.
- **Bloom:** Use `smoothstep` to create a glowing halo around filaments.

## Proposed Code Structure (WGSL)

```wgsl
// ----------------------------------------------------------------
//  Cosmic Web Filament - Generative simulation of dark matter web
//  Category: generative
//  Features: mouse-driven, organic structure
// ----------------------------------------------------------------

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x: time, y: aspect, z: resX, w: resY
  zoom_config: vec4<f32>,  // xy: center, z: zoom, w: unused (Mouse: yz)
  zoom_params: vec4<f32>,  // x: warpStrength, y: density, z: speed, w: colorShift
  ripples: array<vec4<f32>, 50>,
};

// 3D Random Hash
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}

// 3D Voronoi Noise returning F1 and F2
fn voronoi3(p: vec3<f32>) -> vec2<f32> {
    let n = floor(p);
    let f = fract(p);
    var f1 = 1.0;
    var f2 = 1.0;

    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash3(n + g);
                let r = g + o - f;
                let d = dot(r, r);

                if (d < f1) {
                    f2 = f1;
                    f1 = d;
                } else if (d < f2) {
                    f2 = d;
                }
            }
        }
    }
    // Return sqrt distances
    return vec2<f32>(sqrt(f1), sqrt(f2));
}

// FBM for Domain Warping
fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec3<f32>(100.0);
    var p_loop = p;
    for (var i = 0; i < 5; i++) {
        let v_dist = voronoi3(p_loop).x; // Use F1 for cloudiness
        v += a * v_dist;
        p_loop = p_loop * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv_screen = vec2<f32>(global_id.xy) / resolution;
    // Aspect ratio correction
    var uv = (uv_screen - 0.5) * vec2<f32>(resolution.x / resolution.y, 1.0) + 0.5;

    let time = u.config.x * u.zoom_params.z; // Speed control

    // Mouse Interaction (Gravity Well)
    let mouseRaw = u.zoom_config.yz;
    let mouse = (mouseRaw - 0.5) * vec2<f32>(resolution.x / resolution.y, 1.0) + 0.5;
    let isMouseDown = u.zoom_config.w > 0.0; // Use click state or always active?

    let toMouse = mouse - uv;
    let distMouse = length(toMouse);
    let pullStrength = 0.3 * smoothstep(0.8, 0.0, distMouse);

    // Warp UV towards mouse
    uv += normalize(toMouse) * pullStrength;

    // Domain Warping for Organic Look
    var p = vec3<f32>(uv * 3.0, time * 0.1);
    let warp = fbm(p);
    p += vec3<f32>(warp * u.zoom_params.x); // Warp strength

    // Voronoi Cell Calculation
    let v = voronoi3(p);
    let f1 = v.x;
    let f2 = v.y;

    // Filament metric: borders are where F2 - F1 is small
    let border = f2 - f1;
    let filament = 1.0 / (border * 10.0 + 0.05); // Sharpen

    // Density mapping
    let density = smoothstep(0.0, 1.0, filament * u.zoom_params.y);

    // Color Palette
    let colVoid = vec3<f32>(0.05, 0.0, 0.1);
    let colFilament = vec3<f32>(0.2, 0.6, 1.0);
    let colCore = vec3<f32>(1.0, 1.0, 1.0);

    var color = mix(colVoid, colFilament, density);
    color = mix(color, colCore, smoothstep(0.8, 1.0, density));

    // Output
    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

    // Simple depth based on density
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(density, 0.0, 0.0, 0.0));
}
```

## Proposed JSON Definition (`shader_definitions/generative/cosmic-web.json`)

```json
{
  "id": "cosmic-web",
  "name": "Cosmic Web Filament",
  "url": "shaders/cosmic-web.wgsl",
  "category": "generative",
  "description": "Simulates the large-scale structure of the universe with dark matter filaments and voids. Mouse acts as a gravity well.",
  "tags": ["space", "procedural", "organic", "scifi", "dark-matter"],
  "features": ["mouse-driven"],
  "params": [
    {
      "id": "param1",
      "name": "Warp Strength",
      "default": 0.5,
      "min": 0.0,
      "max": 2.0,
      "step": 0.01
    },
    {
      "id": "param2",
      "name": "Filament Density",
      "default": 1.0,
      "min": 0.1,
      "max": 3.0,
      "step": 0.1
    },
    {
      "id": "param3",
      "name": "Flow Speed",
      "default": 0.2,
      "min": 0.0,
      "max": 2.0,
      "step": 0.01
    },
    {
      "id": "param4",
      "name": "Color Shift",
      "default": 0.0,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01
    }
  ]
}
```

## Next Steps
1.  Create `public/shaders/cosmic-web.wgsl` with the code above.
2.  Create `shader_definitions/generative/cosmic-web.json` with the definition above.
3.  Run `npm start` (or `node scripts/generate_shader_lists.js`) to register the shader.
4.  Verify in browser.
