# Shader Upgrade Task: `directional-glitch`

## Metadata
- **Shader ID**: directional-glitch
- **Agent Role**: Algorithmist
- **Current Size**: 3382 bytes
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
//  Directional Glitch
//  Category: interactive-mouse
//  Features: mouse-driven, glitch, audio-reactive, hdr, tonemapped, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let l = 0.4122214708*c.r + 0.5363325363*c.g + 0.0514459929*c.b;
    let m = 0.2119034982*c.r + 0.6806995451*c.g + 0.1073969566*c.b;
    let s = 0.0883024619*c.r + 0.2817188376*c.g + 0.6299787005*c.b;
    let l_ = pow(l, 1.0/3.0); let m_ = pow(m, 1.0/3.0); let s_ = pow(s, 1.0/3.0);
    return vec3<f32>(0.2104542553*l_+0.7936177850*m_-0.0040720468*s_,
                     1.9779984951*l_-2.4285922050*m_+0.4505937099*s_,
                     0.0259040371*l_+0.7827717662*m_-0.8086757660*s_);
}

fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
    let l_ = c.x+0.3963377774*c.y+0.2158037573*c.z;
    let m_ = c.x-0.1055613458*c.y-0.0638541728*c.z;
    let s_ = c.x-0.0894841775*c.y-1.2914855480*c.z;
    let l = l_*l_*l_; let m = m_*m_*m_; let s = s_*s_*s_;
    return vec3<f32>(4.0767416621*l-3.3077115913*m+0.2309699292*s,
                    -1.2684380046*l+2.6097574011*m-0.3413193965*s,
                    -0.0041960863*l-0.7034186147*m+1.7076147010*s);
}

fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    return oklab_to_linear_srgb(mix(linear_srgb_to_oklab(a), linear_srgb_to_oklab(b), t));
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
    let t = clamp(T, 1000.0, 40000.0) / 100.0;
    let r_high = clamp(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0);
    let r = mix(1.0, r_high, step(66.0, t));
    let g_low = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0);
    let g_high = clamp(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0);
    let g = mix(g_low, g_high, step(66.0, t));
    let b_mid = clamp((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0);
    let b = mix(mix(0.0, b_mid, step(19.0, t)), 1.0, step(66.0, t));
    return vec3<f32>(r, g, b);
}

fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    return c * min(1.0, max_lum / max(l, 1e-4));
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 1.0);
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audio_mod = 1.0 + bass * 0.5;

    let intensity = u.zoom_params.x;
    let radius = u.zoom_params.y;
    let scatter = u.zoom_params.z;
    let angle_bias = u.zoom_params.w;

    let uv_c = vec2<f32>(uv.x * aspect, uv.y);
    let mouse_c = vec2<f32>(mouse.x * aspect, mouse.y);
    let dist = distance(uv_c, mouse_c);

    let angle = atan2(uv.y - mouse.y, uv.x - mouse.x) + angle_bias * 6.28;

    let block_id = floor(uv * 50.0);
    let noise = fract(sin(dot(block_id, vec2<f32>(12.9898, 78.233) + time)) * 43758.5453);

    let mask = smoothstep(radius, 0.0, dist);
    let is_glitch = step(1.0 - scatter, noise);

    let disp = is_glitch * intensity * mask * 0.1 * audio_mod;
    let shift = vec2<f32>(cos(angle), sin(angle)) * disp;

    let sr = textureSampleLevel(readTexture, u_sampler, clamp(uv - shift, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let sg = textureSampleLevel(readTexture, u_sampler, clamp(uv - shift * 1.5, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let sb = textureSampleLevel(readTexture, u_sampler, clamp(uv - shift * 2.0, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    var glitch = vec3<f32>(sr.r, sg.g, sb.b) * (1.0 + disp * 12.0);

    let temp = mix(2200.0, 14000.0, clamp(bass * 0.7 + noise * 0.4, 0.0, 1.0));
    glitch = glitch * blackbodyRGB(temp);

    let spark = fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    glitch = glitch + vec3<f32>(spark * mask * intensity * 0.6 * audio_mod);

    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let mixFactor = mask * is_glitch * intensity;
    var color = mixOkLab(original, glitch, mixFactor);

    color = hue_preserve_clamp(color, 3.0);
    color = aces(color);
    let dither = (ign(vec2<f32>(global_id.xy)) - 0.5) / 255.0;
    color = color + vec3<f32>(dither);

    let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
    let alpha = clamp(mix(1.0, 0.35 + 0.65 * luma, mixFactor), 0.3, 1.0);
    let a = clamp(alpha, 0.0, 1.0);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, a));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(color, a));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}

```

## Current JSON Definition
```json
{
  "id": "directional-glitch",
  "name": "Directional Glitch",
  "url": "shaders/directional-glitch.wgsl",
  "description": "Glitch artifacts radiate from the mouse position with audio-reactive displacement.",
  "params": [
    {
      "id": "intensity",
      "name": "Intensity",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.x",
      "description": "Glitch strength"
    },
    {
      "id": "radius",
      "name": "Radius",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.y",
      "description": "Radius of glitch effect"
    },
    {
      "id": "scatter",
      "name": "Scatter",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.z",
      "description": "Scatter and noise amount"
    },
    {
      "id": "angle_bias",
      "name": "Angle Bias",
      "default": 0.5,
      "min": 0,
      "max": 1,
      "step": 0.01,
      "mapping": "zoom_params.w",
      "description": "Directional rotation bias"
    }
  ],
  "features": [
    "mouse-driven",
    "glitch",
    "audio-reactive",
    "upgraded-rgba"
  ],
  "tags": [
    "filter",
    "image-processing",
    "glitch",
    "interactive",
    "audio-reactive"
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
