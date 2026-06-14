# Shader Upgrade Task: `bitonic-sort`

## Metadata
- **Shader ID**: bitonic-sort
- **Agent Role**: Algorithmist
- **Current Size**: 3025 bytes
- **Target Line Count**: ~180 lines
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
// ═══════════════════════════════════════════════════════════════════
//  Bitonic Pixel Sort — Algorithmist Upgrade (May 2026 Batch D)
//  Category: simulation
//  Features: upgraded-rgba, depth-aware, audio-reactive, mouse-driven, multi-ripple
//  Complexity: High
//  Chunks: FBM curl noise, SDF smooth union, true bitonic sort
// ═══════════════════════════════════════════════════════════════════
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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=unused
  zoom_params: vec4<f32>,  // x=SortMix, y=NoiseMix, z=SortDir, w=NoiseOctaves
  ripples: array<vec4<f32>, 50>,
};

var<workgroup> sKey: array<f32, 256>;
var<workgroup> sCol: array<vec4<f32>, 256>;

fn hash22(p: vec2<f32>) -> vec2<f32> {
  let n = sin(dot(p, vec2<f32>(127.1, 311.7)));
  return fract(vec2<f32>(n, n * 43758.5453));
}

fn vnoise(p: vec2<f32>) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash22(i).x, hash22(i + vec2<f32>(1.0, 0.0)).x, u.x),
             mix(hash22(i + vec2<f32>(0.0, 1.0)).x, hash22(i + vec2<f32>(1.0, 1.0)).x, u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
  var s = 0.0;
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    s = s + a * vnoise(pp);
    pp = pp * 2.0 + vec2<f32>(3.1, 1.7);
    a = a * 0.5;
  }
  return s;
}

fn curl2D(p: vec2<f32>) -> vec2<f32> {
  let e = 0.01;
  let n = vnoise(p);
  let dx = vnoise(p + vec2<f32>(e, 0.0)) - n;
  let dy = vnoise(p + vec2<f32>(0.0, e)) - n;
  return vec2<f32>(-dy, dx) / e;
}

fn fbmCurl(p: vec2<f32>, octaves: i32) -> vec2<f32> {
  var v = vec2<f32>(0.0);
  var a = 0.5;
  var pp = p;
  for (var i: i32 = 0; i < octaves; i = i + 1) {
    v = v + a * curl2D(pp);
    pp = pp * 2.0 + vec2<f32>(3.1, 1.7);
    a = a * 0.5;
  }
  return v;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
  let h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

fn rgbToLuma(c: vec3<f32>) -> f32 {
  return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>,
        @builtin(local_invocation_id) lid: vec3<u32>,
        @builtin(workgroup_id) wgid: vec3<u32>) {
  let li = lid.y * 16u + lid.x;
  let gx = wgid.x * 16u + lid.x;
  let gy = wgid.y * 16u + lid.y;
  let x = i32(gx);
  let y = i32(gy);
  let uv = vec2<f32>(f32(gx), f32(gy)) / u.config.zw;
  let time = u.config.x;

  let resX = u32(u.config.z);
  let resY = u32(u.config.w);
  let inBounds = gx < resX && gy < resY;

  let sortMix = u.zoom_params.x;
  let noiseMix = u.zoom_params.y;
  let sortDir = u.zoom_params.z;
  let octaves = max(i32(u.zoom_params.w * 6.0), 1);

  let bass = plasmaBuffer[0].x;
  let bassMod = 1.0 + bass * 0.3;

  let scale = 2.0 + u.zoom_params.w * 10.0;
  let speed = 0.2 + u.zoom_params.y * 0.3;
  let warp = fbmCurl(uv * scale + time * speed, octaves) * (0.02 + u.zoom_params.w * 0.03);
  let warpedUV = uv + warp;

  let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
  var d = distance(uv, mouse) - (0.1 + u.zoom_params.w * 0.2);
  for (var i: i32 = 0; i < 50; i = i + 1) {
    let rp = u.ripples[i];
    if (rp.z > 0.0) {
      let age = time - rp.z;
      if (age > 0.0 && age < 4.0) {
        let rd = distance(uv, rp.xy) - (0.15 * (1.0 - age / 4.0));
        d = smin(d, rd, 0.15);
      }
    }
  }
  let mask = 1.0 - smoothstep(-0.05, 0.05, d);

  var p: vec4<f32>;
  var key: f32;
  if (inBounds) {
    p = textureSampleLevel(readTexture, u_sampler, warpedUV, 0.0);
    let lum = rgbToLuma(p.rgb);
    let n = fbm(uv * 8.0 + time * 0.1, octaves);
    key = lum * (1.0 - noiseMix) + n * noiseMix;
    key = key + f32(li) * 0.00001;
  } else {
    p = vec4<f32>(0.0);
    key = select(-1.0, 2.0, sortDir > 0.5);
  }

  sKey[li] = key;
  sCol[li] = p;

  for (var k: u32 = 2u; k <= 256u; k = k << 1u) {
    for (var j: u32 = k >> 1u; j > 0u; j = j >> 1u) {
      workgroupBarrier();
      let partner = li ^ j;
      let bit = li & k;
      let a = sKey[li];
      let b = sKey[partner];
      let globalAsc = sortDir < 0.5;
      let asc = select(bit != 0u, bit == 0u, globalAsc);
      let swap = select(a > b, a < b, asc);
      if (swap && partner > li) {
        sKey[li] = b;
        sKey[partner] = a;
        let ca = sCol[li];
        sCol[li] = sCol[partner];
        sCol[partner] = ca;
      }
      workgroupBarrier();
    }
  }

  if (inBounds) {
    let sorted = sCol[li];
    let effectiveMix = sortMix * mask * bassMod;
    let finalRgb = mix(p.rgb, sorted.rgb, effectiveMix);
    let alpha = mix(p.a, smoothstep(0.0, 0.3, rgbToLuma(sorted.rgb)), effectiveMix);
    textureStore(writeTexture, vec2<i32>(x, y), vec4<f32>(finalRgb, alpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(x, y), vec4<f32>(depth, 0.0, 0.0, 0.0));
  }
}

```

## Current JSON Definition
```json
{
  "id": "bitonic-sort",
  "name": "Bitonic Pixel Sort",
  "url": "shaders/bitonic-sort.wgsl",
  "description": "Workgroup bitonic pixel sort with FBM-enhanced sort keys, bass-reactive mixing, and semantic luminance-key alpha.",
  "features": [
    "upgraded-rgba",
    "depth-aware",
    "audio-reactive",
    "mouse-driven",
    "multi-ripple"
  ],
  "tags": [
    "simulation",
    "filter",
    "glitch",
    "algorithmic",
    "sort",
    "noise"
  ],
  "params": [
    {
      "id": "param1",
      "name": "Sort Mix",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param2",
      "name": "Noise Mix",
      "default": 0.3,
      "min": 0,
      "max": 1,
      "step": 0.01
    },
    {
      "id": "param3",
      "name": "Sort Direction",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "labels": [
        "Ascending",
        "Descending"
      ]
    },
    {
      "id": "param4",
      "name": "Noise Octaves",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01
    }
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

#### Domain-warped FBM (organic flow, two-octave warp)
```wgsl
fn fbm(p: vec2<f32>) -> f32 {
    var a = 0.5; var s = 0.0; var q = p;
    for (var i = 0; i < 5; i = i + 1) {
        s = s + a * valueNoise(q);
        q = q * 2.02; a = a * 0.5;
    }
    return s;
}
fn warpedFBM(p: vec2<f32>, t: f32) -> f32 {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t)),
                      fbm(p + vec2<f32>(5.2, 1.3)));
    let r = vec2<f32>(fbm(p + 4.0*q + vec2<f32>(1.7, 9.2)),
                      fbm(p + 4.0*q + vec2<f32>(8.3, 2.8)));
    return fbm(p + 4.0*r);
}
```
Strictly better than single-octave noise for "alive" generative shaders. Pass `u.config.x` as `t`.

#### Polar kaleidoscope fold
```wgsl
fn kaleido(uv: vec2<f32>, segs: f32) -> vec2<f32> {
    let r = length(uv);
    var a = atan2(uv.y, uv.x);
    let seg = 6.2831853 / max(segs, 1.0);
    a = abs(((a % seg) + seg) % seg - seg * 0.5);
    return vec2<f32>(cos(a), sin(a)) * r;
}
```
Cheap, branch-light fold that gives instant symmetry. Pair with `warpedFBM` or SDF sampling.

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

#### Smooth-min SDF union (`smin`) — round seams between primitives
```wgsl
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5*(b - a)/k, 0.0, 1.0);
    return mix(b, a, h) - k*h*(1.0 - h);
}
```
`k ≈ 0.1–0.3` of the smaller primitive radius. Replaces hard `min()` for organic blob unions.

#### Anti-aliased SDF / line via `fwidth` (no MSAA needed in compute)
```wgsl
fn aa_step(edge: f32, x: f32) -> f32 {
    let w = max(fwidth(x), 1e-4);
    return smoothstep(edge - w, edge + w, x);
}
```
Use wherever a hard `step()` would produce shimmering edges — kaleidoscope folds, SDF contours, grid lines.

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
4. Ensure the upgraded shader is roughly 180 lines (±20%).
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
