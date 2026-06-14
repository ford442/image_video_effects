# Shader Upgrade Task: `gen-barnsley-fern`

## Metadata
- **Shader ID**: gen-barnsley-fern
- **Agent Role**: Algorithmist
- **Current Size**: 1737 bytes
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
//  Barnsley Fern IFS (Algorithmist Upgrade)
//  Category: generative
//  Features: procedural, fractal, barnsley-ifs, audio-reactive,
//            mouse-driven, aces-tonemap, chromatic-aberration,
//            temporal-feedback, depth-aware, upgraded-rgba,
//            domain-warping, halton-quasi-random
//  Complexity: High
//  Created: 2026-05-30
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Hash, value noise & fBM ───────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
  return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
  let i = floor(p); let f = fract(p); let u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
             mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
  var s = 0.0; var a = 0.5; var f = 1.0;
  for (var i = 0; i < oct; i = i + 1) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
  return s;
}

fn domainWarp(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
  return p + strength * vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
}

// ── Quasi-random Halton sequence ──────────────────────────────────
fn halton(i: u32, base: u32) -> f32 {
  var f = 1.0; var r = 0.0; var idx = i;
  loop { if (idx == 0u) { break; } f = f / f32(base); r += f * f32(idx % base); idx /= base; }
  return r;
}

// ── Color helpers ─────────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32) -> vec3<f32> {
  let a = atan2(uv.y - 0.5, uv.x - 0.5);
  let s = vec2<f32>(cos(a), sin(a)) * strength;
  return vec3<f32>(color.r * (1.0 + s.x * 0.8), color.g, color.b * (1.0 - s.y * 0.5));
}

// ── Inverse IFS transforms ────────────────────────────────────────
fn barnsleyInv(p: vec2<f32>, idx: i32) -> vec2<f32> {
  if idx == 0 { return vec2<f32>(0.0, p.y / 0.16); }
  if idx == 1 { let dy = p.y - 1.6; return vec2<f32>((0.85 * p.x - 0.04 * dy) / 0.7241, (0.04 * p.x + 0.85 * dy) / 0.7241); }
  if idx == 2 { let dy = p.y - 1.6; return vec2<f32>((0.22 * p.x + 0.26 * dy) / 0.1038, (-0.23 * p.x + 0.2 * dy) / 0.1038); }
  let dy = p.y - 0.44; return vec2<f32>((-0.24 * p.x + 0.28 * dy) / 0.1088, (0.26 * p.x + 0.15 * dy) / 0.1088);
}

fn pickIFS(h: f32) -> i32 {
  var idx = 1;
  if h < 0.01 { idx = 0; } else if h < 0.86 { idx = 1; } else if h < 0.93 { idx = 2; } else { idx = 3; }
  return idx;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
  let res = vec2<f32>(u.config.zw);
  let pixel = vec2<i32>(gid.xy);
  if pixel.x >= i32(res.x) || pixel.y >= i32(res.y) { return; }

  let uv01 = vec2<f32>(pixel) / res;
  let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
  let time = u.config.x;
  let mouse = u.zoom_config.yz;
  let bass = plasmaBuffer[0].x;
  let treble = plasmaBuffer[0].z;
  let depth = textureLoad(readDepthTexture, pixel, 0).r;
  let prev = textureLoad(dataTextureC, pixel, 0);

  let scale = mix(0.7, 1.3, u.zoom_params.x);
  let caAmt = u.zoom_params.y * 0.06;
  let brightness = mix(0.8, 2.0, u.zoom_params.z);
  let feedback = u.zoom_params.w;

  let aspect = res.x / max(res.y, 1.0);
  var p = uv * vec2<f32>(aspect * 5.0, 10.0) / scale;

  // Organic domain warp driven by bass + time
  let warp = domainWarp(p * 1.5 + vec2<f32>(time * 0.07, time * 0.05), 0.18 + bass * 0.08, 3);
  p = mix(p, warp, 0.35 + bass * 0.15);

  // Mouse attracts frond tips
  let mouseFern = (mouse - 0.5) * vec2<f32>(aspect * 5.0, 10.0) / scale;
  let tipFactor = smoothstep(0.0, 1.0, (p.y + 3.0) / 8.0);
  let pull = exp(-length(p - mouseFern) * 0.8) * tipFactor * 0.4;
  p = mix(p, mouseFern, pull);

  // Quasi-random inverse IFS Monte-Carlo coverage
  let baseIdx = u32(gid.x) * 73u + u32(gid.y) * 131u + u32(time * 60.0);
  let numPaths = i32(mix(2.0, 5.0, depth + bass * 0.3));
  var density = 0.0;

  for (var path = 0; path < numPaths; path = path + 1) {
    var q = p; var valid = 1.0;
    for (var i = 0; i < 7; i = i + 1) {
      let h = halton(baseIdx + u32(path) * 7u + u32(i), 2u);
      var idx = pickIFS(h);
      if idx == 0 && abs(q.x) > 0.18 { idx = 1; }
      q = barnsleyInv(q, idx);
      let outside = q.x < -3.2 || q.x > 3.2 || q.y < -0.5 || q.y > 12.0;
      if outside { valid = 0.0; break; }
    }
    density += valid;
  }
  density /= f32(numPaths);

  // Multi-scale detail noise modulated by treble
  let detail = fbm(p * 6.0 + vec2<f32>(time * 0.1), 3) * (0.08 + treble * 0.12);
  density = saturate(density * (1.0 + detail) - detail * 0.3);

  // Natural fern palette by height
  let fy = clamp((p.y + 3.0) / 10.0, 0.0, 1.0);
  let forest = vec3<f32>(0.02, 0.18, 0.04);
  let emerald = vec3<f32>(0.05, 0.65, 0.18);
  let lime = vec3<f32>(0.45, 0.95, 0.12);
  let yellow = vec3<f32>(0.85, 0.95, 0.25);
  var color: vec3<f32>;
  if fy < 0.3 { color = mix(forest, emerald, fy / 0.3); }
  else if fy < 0.7 { color = mix(emerald, lime, (fy - 0.3) / 0.4); }
  else { color = mix(lime, yellow, (fy - 0.7) / 0.3); }

  // Sunlight filtering through fronds
  let sun = 0.3 + 0.7 * smoothstep(0.2, 0.9, density);
  color = color * sun * brightness;

  // Chromatic aberration on fern edges
  let edge = smoothstep(0.15, 0.75, density);
  color = genChromaticShift(color, uv01, caAmt * edge);

  color = acesToneMap(color * 1.8);

  // Temporal feedback
  color = mix(color, prev.rgb * 0.96, 0.03 + feedback * 0.08 + bass * 0.02);

  // Audio morphs palette warmth
  let warmth = bass * 0.15;
  color = vec3<f32>(color.r * (1.0 + warmth), color.g, color.b * (1.0 - warmth * 0.3));

  let photo = smoothstep(0.0, 0.4, color.g);
  let alpha = density * photo * (0.4 + depth * 0.6);

  textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
  textureStore(writeDepthTexture, pixel, vec4<f32>(density * depth, 0.0, 0.0, 0.0));
  textureStore(dataTextureA, pixel, vec4<f32>(color, alpha));
}

```

## Current JSON Definition
```json
{
  "id": "gen-barnsley-fern",
  "name": "Barnsley Fern",
  "url": "shaders/gen-barnsley-fern.wgsl",
  "category": "generative",
  "description": "A self-similar fractal fern generated by an iterated function system with 4 affine transformations. Natural forest palette with HDR sunlight filtering through fronds. Audio morphs between fern varieties, mouse attracts frond tips, depth controls leaf detail, and domain warping plus Halton quasi-random sampling add organic motion.",
  "features": [
    "procedural",
    "fractal",
    "barnsley-ifs",
    "audio-reactive",
    "mouse-driven",
    "aces-tonemap",
    "chromatic-aberration",
    "temporal-feedback",
    "depth-aware",
    "upgraded-rgba",
    "domain-warping",
    "halton-quasi-random"
  ],
  "tags": [
    "fractal",
    "fern",
    "nature",
    "green",
    "organic",
    "ifs",
    "mathematical",
    "abstract"
  ],
  "params": [
    {
      "id": "scale",
      "name": "Fern Scale",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Overall size of the fern"
    },
    {
      "id": "chromatic",
      "name": "Chromatic Aberration",
      "default": 0.3,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Color fringe on fern edges"
    },
    {
      "id": "brightness",
      "name": "Sunlight Brightness",
      "default": 0.5,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "HDR sunlight intensity through fronds"
    },
    {
      "id": "feedback",
      "name": "Temporal Feedback",
      "default": 0.2,
      "min": 0.0,
      "max": 1.0,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Ghosting from previous frames"
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
