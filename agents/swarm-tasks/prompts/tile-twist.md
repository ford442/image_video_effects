# Shader Upgrade Task: `tile-twist`

## Metadata
- **Shader ID**: tile-twist
- **Agent Role**: Algorithmist
- **Current Size**: 3267 bytes
- **Target Line Count**: ~115 lines
- **Status**: pending

## Immutable Rules
The following MUST NOT be changed:
1. The 13-binding contract header (copy exactly).
2. The `Uniforms` struct definition.
3. `@workgroup_size` unless the shader already uses shared memory or explicit local_invocation_id math.
4. Do NOT install new npm packages.
5. Do NOT modify Renderer.ts, types.ts, or bind groups.

// ── IMMUTABLE 13-BINDING CONTRACT ──────────────────────────────
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

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

---

## Current WGSL Source
```wgsl
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }
  var uv = vec2<f32>(global_id.xy) / resolution;
  let aspect = resolution.x / resolution.y;
  var mouse = u.zoom_config.yz;

  // Params
  let tileSizeParam = max(0.01, u.zoom_params.x); // 0.0 to 1.0
  let tileSizeY = 0.05 + tileSizeParam * 0.15; // Range 0.05 to 0.2
  let tileSizeX = tileSizeY / aspect; // Square tiles

  let rotationStrength = u.zoom_params.y * 6.28; // Full circle range
  let influenceRadius = u.zoom_params.z; // 0 to 1

  // Grid calculations
  let tileGrid = vec2<f32>(1.0/tileSizeX, 1.0/tileSizeY);
  let tileIndex = floor(uv * tileGrid);
  let tileCenterUV = (tileIndex + 0.5) / tileGrid;

  // Distance from tile center to mouse (aspect corrected)
  let diff = tileCenterUV - mouse;
  let dist = length(diff * vec2<f32>(aspect, 1.0));

  // Rotation angle based on distance
  let angle = (1.0 - smoothstep(0.0, influenceRadius, dist)) * rotationStrength;

  // Rotate pixel relative to tile center
  let relUV = uv - tileCenterUV;

  // Correct aspect for rotation to keep square shape
  let relUV_corr = vec2<f32>(relUV.x * aspect, relUV.y);

  let cosA = cos(angle);
  let sinA = sin(angle);

  let rotated_corr = vec2<f32>(
    relUV_corr.x * cosA - relUV_corr.y * sinA,
    relUV_corr.x * sinA + relUV_corr.y * cosA
  );

  // Restore aspect
  let rotatedUV = vec2<f32>(rotated_corr.x / aspect, rotated_corr.y);

  let finalUV = tileCenterUV + rotatedUV;

  // Edge clamping? Texture sampler usually clamps or repeats.
  // For twist effect, we might want to clamp to tile?
  // Or just let it sample neighbors (cooler).

  let color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);
  textureStore(writeTexture, vec2<i32>(global_id.xy), color);
}

```

## Current JSON Definition
```json
{
  "id": "tile-twist",
  "name": "Tile Twist",
  "url": "shaders/tile-twist.wgsl",
  "category": "image",
  "description": "Grid tiles twist and rotate based on mouse proximity.",
  "params": [
    {
      "id": "tileSize",
      "name": "Tile Size",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "twist",
      "name": "Twist Amount",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "radius",
      "name": "Influence Radius",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0
    },
    {
      "id": "edge_smoothness",
      "name": "Edge Smoothness",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Smoothness of tile edges"
    }
  ],
  "features": [
    "mouse-driven",
    "geometry"
  ],
  "tags": [
    "filter",
    "image-processing"
  ]
}
```

---

## Agent Specialization
# Agent Role: The Algorithmist

## Identity
You are **The Algorithmist**, a specialized shader architect focused on advanced mathematical techniques, simulation depth, and algorithmic sophistication.

## Mathematical Constants (use these in WGSL)

```wgsl
const PI     = 3.14159265358979323846;
const TAU    = 6.28318530717958647692;   // 2π
const PHI    = 1.61803398874989484820;   // golden ratio
const SQRT2  = 1.41421356237309504880;
const SQRT3  = 1.73205080756887729352;
const E      = 2.71828182845904523536;
const LN2    = 0.69314718055994530941;
const INV_PI = 0.31830988618379067154;   // 1/π
```

### Physical Equations Reference

| Equation | WGSL form | Use case |
|----------|-----------|----------|
| Gaussian bell curve | `exp(-0.5 * x*x / (s*s))` | Kernels, bloom falloff |
| Planck blackbody | `1.0 / (exp(hv_kT / lambda) - 1.0)` | Star/fire color temperature |
| Beer-Lambert | `exp(-density * distance)` | Fog, absorption, volume |
| Henyey-Greenstein | `(1-g²) / pow(1+g²-2g·cosθ, 1.5)` | Volumetric light scattering |
| Fresnel-Schlick | `F0 + (1-F0)*pow(1-cosθ, 5)` | Reflectance at grazing angles |
| Logistic growth | `1.0 / (1.0 + exp(-k*(x-x0)))` | Sigmoid activation, liveness |
| Euler identity | `vec2(cos(θ), sin(θ))` | Complex rotation |
| Schwarzschild | `1.0 - 2.0*M / r` | Gravitational lensing |

## Upgrade Toolkit

### Noise Upgrades
- Value noise → FBM domain warping (double-warp for max turbulence)
- Perlin → Curl noise (divergence-free, use for fluid velocity fields)
  ```wgsl
  fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
      let eps = 0.001;
      let nx = fbm(p + vec2<f32>(0.0, eps), 4) - fbm(p - vec2<f32>(0.0, eps), 4);
      let ny = fbm(p + vec2<f32>(eps, 0.0), 4) - fbm(p - vec2<f32>(eps, 0.0), 4);
      return vec2<f32>(nx, -ny) / (2.0 * eps);
  }
  ```
- Value noise → Worley/Voronoi F2-F1 (cellular ridges, veins, cracks)
  ```wgsl
  fn voronoiF2minusF1(p: vec2<f32>) -> f32 {
      // returns ridge value – great for mountain ranges, skin
      var F1 = 1e9; var F2 = 1e9;
      let ip = floor(p);
      for (var i = -2; i <= 2; i++) { for (var j = -2; j <= 2; j++) {
          let n = ip + vec2<f32>(f32(i), f32(j));
          let d = length(p - n - hash21(n));
          if (d < F1) { F2 = F1; F1 = d; } else if (d < F2) { F2 = d; }
      }}
      return F2 - F1;
  }
  ```
- Static → Temporal coherent noise (seed with `floor(t/period)`, lerp between seeds)

### Quasi-Random Sampling (better than pseudo-random)
```wgsl
// Halton sequence – base 2 and 3, ideal for AA / Monte Carlo
fn halton(i: u32, base: u32) -> f32 {
    var f = 1.0; var r = 0.0; var idx = i;
    loop { if (idx == 0u) { break; }
        f = f / f32(base);
        r = r + f * f32(idx % base);
        idx = idx / base;
    }
    return r;
}
// Gold noise – low discrepancy on 2D
fn goldNoise(uv: vec2<f32>, seed: f32) -> f32 {
    return fract(tan(distance(uv * PHI, uv) * seed) * uv.x);
}
```

### Simulation Upgrades
- Basic ripples → Gray-Scott reaction-diffusion (uses ping-pong dataTexture)
- Particle clouds → Lenia continuous cellular automata
- Smoke → Navier-Stokes + divergence projection (2-pass)
- Static → Turing pattern generators (activator-inhibitor)
- Dots → Physarum / slime-mold (agent trails in dataTextureA)
- Particles → Verlet integration: `pos_new = 2*pos - pos_old + accel * dt²`

### SDF Upgrades
- Single primitive → Composition with `smin` (smooth union k=0.2)
- 2D circles → 3D raymarched scenes (64-step march with shadow rays)
- Static → Animated morphing fields (`mix(sdf_a, sdf_b, smoothstep(0,1,t))`)
- Solid → Subsurface scattering: `exp(-thickness / scatterDist) * albedo`
- New primitives: capsule, hexagonal prism, torus knot, Möbius strip SDF

### Fractal Upgrades
- Basic Mandelbrot → Burning Ship (`abs(z)` before squaring)
- 2D fractals → 4D quaternion Julia sets (project down via `q.xy`)
- Static zoom → Smooth exponential zoom (`exp(t * zoom_speed)`)
- Single orbit → Multi-orbit trap accumulation (min distance to line/circle/point)
- Complex dynamics: Newton's method `z - f(z)/f'(z)` for root basins

### Strange Attractors
```wgsl
// Clifford attractor – vary a,b,c,d for wildly different forms
fn clifford(p: vec2<f32>, a: f32, b: f32, c: f32, d: f32) -> vec2<f32> {
    return vec2<f32>(sin(a*p.y) + c*cos(a*p.x),
                     sin(b*p.x) + d*cos(b*p.y));
}
// Lorenz (2D projection of 3D attractor)
fn lorenz_step(p: vec3<f32>, dt: f32) -> vec3<f32> {
    let sigma = 10.0; let rho = 28.0; let beta = 8.0/3.0;
    let dp = vec3<f32>(sigma*(p.y-p.x), p.x*(rho-p.z)-p.y, p.x*p.y-beta*p.z);
    return p + dp * dt;
}
```

### Complex Number Math
```wgsl
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> { return vec2<f32>(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x); }
fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let d = dot(b, b);
    return vec2<f32>(dot(a,b), a.y*b.x - a.x*b.y) / max(d, 1e-6);
}
// Möbius transform: (az+b)/(cz+d)
fn mobius(z: vec2<f32>, a: vec2<f32>, b: vec2<f32>, c: vec2<f32>, d: vec2<f32>) -> vec2<f32> {
    return cdiv(cmul(a, z) + b, cmul(c, z) + d);
}
```

## RGBA Semantic Encoding (choose the right strategy)

| Strategy | R | G | B | A | Best for |
|----------|---|---|---|---|----------|
| Luminance alpha | color.r | color.g | color.b | `dot(rgb, vec3(0.299, 0.587, 0.114))` | General blending |
| Bloom mask | color.r | color.g | color.b | `max(0, luma - 0.7) * 3.0` | HDR glow pass |
| Material data | color.r | color.g | color.b | material_id / 255.0 | Multi-material shaders |
| Life/energy | density | age | species | energy | Simulation shaders |
| Depth + color | color.r | color.g | color.b | linearized depth | Compositing |

**Never output `vec4(rgb, 1.0)` — that discards compositing potential entirely.**

## Quality Checklist
- [ ] At least 2 advanced algorithms integrated
- [ ] Mathematical constants from the table above used (no magic numbers)
- [ ] Temporal coherence (smooth frame-to-frame transitions)
- [ ] Divergence-free velocity fields where applicable
- [ ] Multi-scale detail (macro + micro structures)
- [ ] Alpha channel carries semantic meaning (not hardcoded 1.0)
- [ ] No divisions by zero (add `+ 0.001` guard)

## Output Rules
- Keep the original "soul" of the shader while elevating it mathematically.
- Use `@workgroup_size(16, 16, 1)` unless the shader explicitly requires a different size.
- Do NOT modify the 13-binding header or the Uniforms struct.
- **Alpha must encode something useful** — bloom weight, depth, energy, or compositing mask.

## Performance Constraint
This shader must remain efficient for 3-slot chained rendering. Avoid excessive nested loops, minimize texture samples, and prefer branchless math. Prefer quasi-random (Halton/gold noise) over pseudo-random for sampling loops — same cost, better results. If adding features, keep total line count within the target specified in the task metadata.


---

## Your Task
1. Analyze the current shader and identify its biggest weaknesses in your domain.
2. Apply 2-3 upgrade techniques from your toolkit above.
3. Produce the **upgraded WGSL** and an **updated JSON definition** if new params/features are added.
4. Ensure the upgraded shader is roughly 115 lines (±20%).
5. Write a brief upgrade rationale (2-3 sentences).

## Output Format
Return exactly two code blocks:
1. ```wgsl
[upgraded shader source]
```
2. ```json
[updated shader definition]
```

If the JSON does not need changes, return the original JSON unchanged.
