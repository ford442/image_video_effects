# Shader Upgrade Task: `gen-von-karman-vortex`

## Metadata
- **Shader ID**: gen-von-karman-vortex
- **Agent Role**: Algorithmist
- **Current Size**: 1420 bytes
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
//  Von Kármán Vortex Street — Upgraded
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba, curl-noise,
//            domain-warp, analytic-velocity, temporal-feedback,
//            chromatic-aberration, aces-tone-map, semantic-alpha
//  Complexity: Medium
//  Description: Analytic point-vortex street with divergence-free
//    curl-noise perturbation and fBM domain warping. Velocity is
//    computed analytically from the vortex model rather than by
//    finite differences. Bass drives shedding speed and micro-
//    turbulence; mids control trail decay. Mouse positions the
//    obstacle.
// ═══════════════════════════════════════════════════════════════════
//  zoom_params: x=flow_speed, y=vortex_separation, z=vortex_spacing, w=hue

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
  config:      vec4<f32>,  // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>,  // x=speed, y=separation, z=spacing, w=hue
  ripples: array<vec4<f32>, 50>,
};

const PI: f32      = 3.14159265359;
const TAU: f32     = 6.28318530718;
const INV_TAU: f32 = 0.15915494309;
const N_VTX: i32   = 10;
const CORE_R: f32  = 0.04;

// ── Hash & noise library ──────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}

// Divergence-free velocity perturbation for organic, incompressible detail
fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.001;
    let q = p + vec2<f32>(0.0, t);
    let nx = fbm(q + vec2<f32>(0.0, eps), 4) - fbm(q - vec2<f32>(0.0, eps), 4);
    let ny = fbm(q + vec2<f32>(eps, 0.0), 4) - fbm(q - vec2<f32>(eps, 0.0), 4);
    return vec2<f32>(nx, -ny) / (2.0 * eps);
}

// ── Color utilities ───────────────────────────────────────────────
fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn streamline_color(t: f32, hueShift: f32, speed: f32) -> vec3<f32> {
    let h = fract(t + hueShift);
    let a = vec3<f32>(0.55, 0.55, 0.55);
    let b = vec3<f32>(0.45, 0.45, 0.45);
    let c = vec3<f32>(1.00, 1.00, 1.00);
    let d = vec3<f32>(0.00, 0.33, 0.67);
    let base = clamp(a + b * cos(TAU * (c * h + d)), vec3<f32>(0.0), vec3<f32>(1.0));
    return base * (0.6 + 0.4 * clamp(speed * 0.5, 0.0, 1.0));
}

// ── Analytic vortex street ────────────────────────────────────────
// Returns vec3(psi, velocity_x, velocity_y) for N point-vortex pairs.
// Streamfunction: ψ = U·y + Σ (Γ_i/2π)·ln(r_i)
// Velocity:       u = ∂ψ/∂y,  v = -∂ψ/∂x
fn vortex_field(pos: vec2<f32>, time: f32, U: f32,
                h: f32, spacing: f32, obst: vec2<f32>) -> vec3<f32> {
    var psi = U * pos.y;
    var vel = vec2<f32>(U, 0.0);
    let domainW = f32(N_VTX) * spacing;
    let phase   = fract(U * time / domainW);
    let core2   = CORE_R * CORE_R;

    for (var i = 0; i < N_VTX; i = i + 1) {
        let fi = f32(i);
        let xT = obst.x + (fi / f32(N_VTX) - phase) * domainW - domainW * 0.5;
        let xB = obst.x + ((fi + 0.5) / f32(N_VTX) - phase) * domainW - domainW * 0.5;
        let yT = obst.y + h;
        let yB = obst.y - h;

        let dT = pos - vec2<f32>(xT, yT);
        let dB = pos - vec2<f32>(xB, yB);
        let rT2 = max(dot(dT, dT), core2);
        let rB2 = max(dot(dB, dB), core2);

        // Top row Γ = +1, bottom row Γ = -1
        psi += log(rT2) * INV_TAU * 0.5;
        psi -= log(rB2) * INV_TAU * 0.5;
        vel += vec2<f32>(dT.y, -dT.x) / (TAU * rT2);
        vel -= vec2<f32>(dB.y, -dB.x) / (TAU * rB2);
    }
    return vec3<f32>(psi, vel);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let pixel = vec2<i32>(gid.xy);
    let res   = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv01   = vec2<f32>(gid.xy) / res;
    let time   = u.config.x;
    let mouse  = u.zoom_config.yz;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth  = textureLoad(readDepthTexture, pixel, 0).r;
    let prev   = textureLoad(dataTextureC, pixel, 0);

    // UI parameters
    let U        = (0.20 + u.zoom_params.x * 0.50) * (1.0 + bass * 0.6);
    let h        = 0.10 + u.zoom_params.y * 0.25 + mids * 0.05;
    let spacing  = 0.35 + u.zoom_params.z * 0.40;
    let hueShift = u.zoom_params.w;

    // Aspect-correct physical coordinates; mouse drives obstacle position
    let aspect  = res.x / res.y;
    let physPos = (uv01 - 0.5) * vec2<f32>(2.0 * aspect, 2.0);
    let obst    = vec2<f32>((mouse.x - 0.5) * 2.0 * aspect,
                            (mouse.y - 0.5) * 2.0);

    // Divergence-free curl-noise perturbation + fBM domain warp
    let noiseCoord = physPos * 2.5 + vec2<f32>(time * 0.13, -time * 0.07);
    let turb       = curl2D(noiseCoord, time * 0.2);
    let warpStr    = 0.015 + mids * 0.025 + bass * 0.015;
    let warpedPos  = physPos + turb * warpStr + vec2<f32>(
        fbm(physPos * 3.0 + vec2<f32>(time * 0.05, 1.3), 3) - 0.5,
        fbm(physPos * 3.0 + vec2<f32>(5.2, -time * 0.04), 3) - 0.5
    ) * 0.02;

    // Evaluate streamfunction and analytic velocity
    let field = vortex_field(warpedPos, time, U, h, spacing, obst);
    let psi   = field.x;
    let vel   = field.yz;
    let spd   = length(vel);

    // Obstacle mask — darken the immediate disk around the mouse
    let obstDist = length(physPos - obst);
    let obstMask = smoothstep(0.05, 0.09, obstDist);

    // Streamline contours; treble injects extra fine lines
    let nLines   = 6.0 + treble * 4.0;
    let psiNorm  = fract(psi * nLines * 0.15);
    let lineW    = 0.05 + 0.05 * mids;
    let lineGlow = exp(-abs(psiNorm - 0.5) / lineW);

    // Base streamline colour with speed-dependent saturation
    var col = streamline_color(psi * 0.05 + spd * 0.02, hueShift, spd);
    col *= lineGlow * obstMask;

    // Speed halo around vortex cores
    let speedHalo = clamp(spd * 0.12, 0.0, 1.0);
    col = clamp(col + vec3<f32>(speedHalo * 0.25 * (1.0 + bass)), vec3<f32>(0.0), vec3<f32>(1.0));

    // Temporal feedback: decaying trails blended with current frame
    let decay = 0.96 - mids * 0.03;
    col = mix(prev.rgb * decay, col, 0.18 + bass * 0.12);

    // Chromatic aberration radiating from screen centre, driven by bass + depth
    let caStr = 0.003 * (1.0 + bass) + depth * 0.0015;
    let dir   = normalize(uv01 - vec2<f32>(0.5) + vec2<f32>(0.001));
    col = vec3<f32>(
        col.r + dir.x * caStr,
        col.g,
        col.b - dir.y * caStr * 0.5
    );

    // Tone map and semantic alpha (intensity + depth compositing)
    col = acesToneMap(col * 1.15);
    let alpha = clamp(luma(col) * 1.4 + speedHalo * 0.2 + bass * 0.06, 0.0, 0.95)
                * (0.75 + depth * 0.25);
    let outCol = vec4<f32>(col, alpha);

    textureStore(writeTexture, pixel, outCol);
    textureStore(dataTextureA, pixel, outCol);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "gen-von-karman-vortex",
  "name": "Von Kármán Vortex Street",
  "url": "shaders/gen-von-karman-vortex.wgsl",
  "description": "Analytic vortex-street flow visualization. Ten alternating point-vortex pairs shed behind the mouse-driven obstacle; their combined streamfunction ψ = U·y + Σ ±(Γ/2π)·ln(r) produces isocontours tracing the classic Kármán street wake. Bass drives shedding speed; mids vary vortex separation for staggered or aligned rows.",
  "tags": [
    "fluid-dynamics",
    "vortex",
    "karman",
    "analytic",
    "physics",
    "audio-reactive"
  ],
  "features": [
    "mouse-driven",
    "audio-reactive",
    "procedural",
    "temporal",
    "chromatic",
    "depth-aware",
    "upgraded-rgba"
  ],
  "params": [
    {
      "id": "flowSpeed",
      "name": "Flow Speed",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x"
    },
    {
      "id": "vortexSeparation",
      "name": "Vortex Separation",
      "default": 0.4,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y"
    },
    {
      "id": "vortexSpacing",
      "name": "Vortex Spacing",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z"
    },
    {
      "id": "hue",
      "name": "Colour Hue",
      "default": 0,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w"
    }
  ],
  "coordinate": 887
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
