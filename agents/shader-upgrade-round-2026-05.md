# Shader Upgrade Round — May 2026

> **Date:** 2026-05-10
> **Scope:** Next 25 shaders from the candidate pool
> **Methodology:** Three-phase swarm — Analysis → Design → Implementation
> **Constraint:** Do NOT modify `Renderer.ts`, `types.ts`, bind group layouts, or install npm packages.

---

## Context

Previous rounds (Batch A/B/C) completed 25 shaders. This prompt drives the **next batch** using the same three-phase swarm methodology documented in:
- `agents/swarm-spec-shader-upgrade-phases.yaml` — full phase spec and agent roles
- `agents/4_AGENT_SWARM_PROMPT.md` — 4-agent roles (Algorithmist, Visualist, Interactivist, Optimizer)
- `agents/upgrade_swarm.md` — mathematical function library
- `agents/EFFECT_UPGRADE_SWARM.md` — per-shader upgrade plans
- `agents/weekly_upgrade_swarm.md` — completed shaders, candidate pool, code patterns

---

## Target Shaders (Batch D)

These are drawn directly from the `weekly_upgrade_swarm.md` candidate pool, ordered by file size:

| # | Shader ID | File Size | Category | Priority Issues |
|---|-----------|-----------|----------|-----------------|
| D1 | `bitonic-sort` | 3,025 | post-processing | Workgroup size, RGBA, audio |
| D2 | `temporal-rgb-smear` | 3,065 | visual-effects | Workgroup size, RGBA, smear direction |
| D3 | `elastic-chromatic` | 3,089 | distortion | Workgroup size, RGBA, plasmaBuffer |
| D4 | `waveform-glitch` | 3,117 | retro-glitch | Workgroup size, RGBA, VHS enhancements |
| D5 | `data-slicer-interactive` | 3,163 | distortion | Workgroup size, RGBA, interactivity |
| D6 | `pixel-stretch-cross` | 3,163 | distortion | Workgroup size, RGBA, depth |
| D7 | `interactive-magnetic-ripple` | 3,166 | interactive-mouse | Workgroup size, RGBA, multi-ripple |
| D8 | `luma-pixel-sort` | 3,192 | post-processing | Workgroup size, RGBA, sort quality |
| D9 | `pixel-depth-sort` | 3,195 | post-processing | Workgroup size, RGBA, depth-aware |
| D10 | `pixel-sand` | 3,208 | simulation | Workgroup size, RGBA, physics |
| D11 | `phosphor-decay` | 3,215 | retro-glitch | Workgroup size, RGBA, CRT accuracy |
| D12 | `crt-magnet` | 3,230 | retro-glitch | Workgroup size, RGBA, color bloom |
| D13 | `scan-distort-gpt52` | 3,236 | distortion | Workgroup size, RGBA, multi-band |
| D14 | `digital-lens` | 3,238 | distortion | Workgroup size, RGBA, lens model |
| D15 | `chromatic-mosaic-projector` | 3,242 | distortion | Workgroup size, RGBA, projection |
| D16 | `chrono-slit-scan` | 3,242 | artistic | Workgroup size, RGBA, temporal |
| D17 | `mosaic-reveal` | 3,247 | distortion | Workgroup size, RGBA, reveal quality |
| D18 | `quad-mirror` | 3,256 | geometric | Workgroup size, RGBA, seam handling |
| D19 | `spiral-lens` | 3,266 | distortion | Workgroup size, RGBA, lens model |
| D20 | `tile-twist` | 3,267 | distortion | Workgroup size, RGBA, tiling |
| D21 | `page-curl-interactive` | 3,284 | interactive-mouse | Workgroup size, RGBA, curl physics |
| D22 | `tesseract-fold` | 3,286 | geometric | Workgroup size, RGBA, 4D math |
| D23 | `polar-warp-interactive` | 3,287 | interactive-mouse | Workgroup size, RGBA, polar math |
| D24 | `echo-ripple` | 3,307 | artistic | Workgroup size, RGBA, ripple system |
| D25 | `scanline-wave` | 3,315 | retro-glitch | Workgroup size, RGBA, CRT quality |

---

## Mandatory Technical Spec

Every upgraded shader MUST conform to these requirements. Non-conformance fails QA.

### Standard 13-Binding Header

```wgsl
// --- STANDARD BINDING HEADER (copy verbatim) ---
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
// -----------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};
```

### Entry Point

```wgsl
@compute @workgroup_size(8, 8, 1)   // ← MUST be (8,8,1), NOT (16,16,1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    // ...
    textureStore(writeTexture, coord, vec4<f32>(rgb, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```

### Uniform Field Reference

| Field | Usage |
|-------|-------|
| `u.config.x` | Time (seconds, continuous) |
| `u.config.y` | Click count / generic seed |
| `u.config.zw` | Resolution (width, height) |
| `u.zoom_config.yz` | Mouse position (0–1 normalized) |
| `u.zoom_params.x` | Param1 — slider value 0.0–1.0 |
| `u.zoom_params.y` | Param2 — slider value 0.0–1.0 |
| `u.zoom_params.z` | Param3 — slider value 0.0–1.0 |
| `u.zoom_params.w` | Param4 — slider value 0.0–1.0 |
| `plasmaBuffer[0].x` | Bass energy (0–1) |
| `plasmaBuffer[0].y` | Mid energy (0–1) |
| `plasmaBuffer[0].z` | Treble energy (0–1) |
| `u.ripples[i]` | Ripple point i: xy=position, z=time, w=intensity |

---

## Phase 1: Analysis

**Each shader agent reads its assigned WGSL file and JSON definition and fills in this audit table:**

```
Shader: <id>
File:   public/shaders/<id>.wgsl
JSON:   shader_definitions/<category>/<id>.json

Defects found:
  [ ] Workgroup size is (16,16,1) — must fix to (8,8,1)
  [ ] Alpha hardcoded to 1.0 — must add semantic alpha
  [ ] writeDepthTexture not written — must add depth pass-through
  [ ] No plasmaBuffer audio reactivity — must wire to at least 1 parameter
  [ ] zoom_params has unused/dead slots — must define all 4 params
  [ ] Params have dead zones (black/blank output at extremes)
  [ ] RGB-only sampling without preserving source alpha
  [ ] JSON missing features[] or params[] array

Current effect summary (1 sentence):

3 biggest weaknesses:
  1.
  2.
  3.

Upgrade opportunity (1 sentence):
```

---

## Phase 2: Design

For each shader, define the full upgrade plan before writing any code.

### 2a. Shared Mathematical Utilities

All upgraded shaders may freely use these functions — paste into the shader above the main function:

```wgsl
// ══ HASH & NOISE ══════════════════════════════════════════════════
fn hash11(p: f32) -> f32 { return fract(sin(p * 127.1) * 43758.5453); }
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    return fract(sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)),
                               dot(p, vec2<f32>(269.5, 183.3)))) * 43758.5453);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1,0)), u.x),
               mix(hash21(i + vec2<f32>(0,1)), hash21(i + vec2<f32>(1,1)), u.x), u.y);
}
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var s = 0.0; var a = 0.5; var pp = p;
    for (var i = 0; i < octaves; i++) { s += a * valueNoise(pp); pp *= 2.0; a *= 0.5; }
    return s;
}
fn curlNoise(p: vec2<f32>) -> vec2<f32> {
    let e = 0.001;
    return vec2<f32>(valueNoise(p + vec2<f32>(0,e)) - valueNoise(p - vec2<f32>(0,e)),
                    -(valueNoise(p + vec2<f32>(e,0)) - valueNoise(p - vec2<f32>(e,0)))) / (2.0*e);
}

// ══ COLOR UTILITIES ════════════════════════════════════════════════
fn rgbToLuma(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.299, 0.587, 0.114)); }
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let c = hsv.z * hsv.y; let h6 = hsv.x * 6.0;
    let x = c * (1.0 - abs(fract(h6 * 0.5) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0) { rgb = vec3<f32>(c,x,0); } else if (h6 < 2.0) { rgb = vec3<f32>(x,c,0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0,c,x); } else if (h6 < 4.0) { rgb = vec3<f32>(0,x,c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x,0,c); } else { rgb = vec3<f32>(c,0,x); }
    return rgb + vec3<f32>(hsv.z - c);
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn schlickFresnel(cosTheta: f32, R0: f32) -> f32 {
    return R0 + (1.0 - R0) * pow(max(1.0 - cosTheta, 0.0), 5.0);
}

// ══ SDF PRIMITIVES ══════════════════════════════════════════════════
fn sdCircle(p: vec2<f32>, r: f32) -> f32 { return length(p) - r; }
fn sdBox(p: vec2<f32>, b: vec2<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec2<f32>(0.0))) + min(max(d.x,d.y), 0.0);
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5*(b-a)/k, 0.0, 1.0);
    return mix(b, a, h) - k*h*(1.0-h);
}

// ══ GEOMETRIC CURVES ═══════════════════════════════════════════════
fn rotate2D(v: vec2<f32>, a: f32) -> vec2<f32> {
    return vec2<f32>(v.x*cos(a) - v.y*sin(a), v.x*sin(a) + v.y*cos(a));
}
fn lissajous(t: f32, A: f32, B: f32, a: f32, b: f32, delta: f32) -> vec2<f32> {
    return vec2<f32>(A * sin(a*t + delta), B * sin(b*t));
}
fn fibonacciDisk(i: i32, n: i32) -> vec2<f32> {
    let r = sqrt(f32(i) / f32(max(n,1)));
    let theta = f32(i) * 2.3999632297; // golden angle
    return vec2<f32>(cos(theta), sin(theta)) * r;
}

// ══ CONVOLUTION KERNELS ════════════════════════════════════════════
const GAUSSIAN_3X3: array<f32, 9> = array<f32, 9>(
    0.0625, 0.125, 0.0625,
    0.125,  0.25,  0.125,
    0.0625, 0.125, 0.0625
);
const SOBEL_GX: array<f32, 9> = array<f32, 9>(
    -1.0, 0.0, 1.0, -2.0, 0.0, 2.0, -1.0, 0.0, 1.0
);
const SOBEL_GY: array<f32, 9> = array<f32, 9>(
    -1.0, -2.0, -1.0, 0.0, 0.0, 0.0, 1.0, 2.0, 1.0
);
```

### 2b. Per-Shader Upgrade Plan Template

For each shader, document before implementing:

```
Shader: <id>

ALPHA STRATEGY:
  Type: [luminance-key | depth-layered | edge-preserve | accumulative | effect-mask]
  Formula: <exact WGSL expression for alpha>

AUDIO REACTIVITY:
  plasmaBuffer[0].x (bass) → <which param or formula>
  plasmaBuffer[0].y (mids) → <which param or formula, or "unused">
  plasmaBuffer[0].z (treble) → <which param, or "unused">

ZOOM_PARAMS MAPPING:
  x (Param1): <name> — <range mapping> — <visual effect>
  y (Param2): <name> — <range mapping> — <visual effect>
  z (Param3): <name> — <range mapping> — <visual effect>
  w (Param4): <name> — <range mapping> — <visual effect>

RANDOMIZATION SAFETY:
  [ ] All 4 params produce non-black output at 0.0
  [ ] All 4 params produce non-black output at 1.0
  [ ] No division by zero (add epsilon where needed)

MATHEMATICAL UPGRADES (pick ≥1 from each agent domain):
  Algorithmist: [FBM | curl-noise | reaction-diffusion | SDF | Lissajous | Fibonacci]
  Visualist: [HDR | tone-map | Fresnel | spectral | volumetric | color-temperature]
  Interactivist: [depth-aware | mouse-gravity | ripple-system | temporal-feedback]
  Optimizer: [early-exit | kernel-cache | LOD-quality | precomputed-constants]

NEW LINE COUNT TARGET: <current> → <target, minimum +30 lines of meaningful logic>
```

---

## Phase 3: Implementation

Execute these upgrades in the order listed. For each shader:

### Step 1 — Fix workgroup size

```wgsl
// BEFORE:
@compute @workgroup_size(16, 16, 1)

// AFTER:
@compute @workgroup_size(8, 8, 1)
```

### Step 2 — Bounds check

Immediately after entry, add bounds guard if missing:
```wgsl
if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
```

### Step 3 — Replace RGB-only sampling with RGBA

```wgsl
// BEFORE: let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
// AFTER:
let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);  // full vec4
// Use src.rgb for color, preserve src.a through blending
```

### Step 4 — Add depth pass-through

Every shader that doesn't already write a meaningful depth value must at minimum pass depth through:
```wgsl
let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
```

### Step 5 — Define semantic alpha

Choose the alpha strategy appropriate to the shader type:

```wgsl
// Luminance-key (for additive/glow effects):
let alpha = smoothstep(0.0, 0.5, rgbToLuma(finalRgb));

// Effect-mask (for distortion/reveal effects):
let alpha = mix(src.a, 1.0, effectStrength);

// Depth-layered (for 3D/volumetric effects):
let alpha = mix(0.5, 1.0, depth);

// Accumulative (for temporal/trail effects):
let alpha = clamp(history.a * decay + newContrib, 0.0, 1.0);

// Edge-preserve (for filter/processing effects):
let edgeMag = length(vec2<f32>(sobelX, sobelY));
let alpha = mix(src.a, 1.0, smoothstep(0.1, 0.5, edgeMag));
```

### Step 6 — Wire audio reactivity

```wgsl
let bass   = plasmaBuffer[0].x;  // 0–1, beat energy
let mids   = plasmaBuffer[0].y;  // 0–1, melody energy
let treble = plasmaBuffer[0].z;  // 0–1, shimmer energy

// Example: bass expands effect radius
let effectRadius = baseRadius * (1.0 + bass * 0.4);

// Example: mids modulate color hue
let hueOffset = mids * 0.2;

// Example: treble adds sparkle brightness
let brightness = 1.0 + treble * 0.3;
```

### Step 7 — Validate zoom_params randomization safety

Every parameter used in a denominator or as a loop count must be guarded:
```wgsl
// Safe division:
let freq = mix(2.0, 20.0, u.zoom_params.x);       // never 0
let samples = i32(mix(8.0, 32.0, u.zoom_params.y)); // always ≥ 8

// Unsafe patterns to fix:
// BAD:  let t = u.zoom_params.x;  // can be 0 in denominator
// GOOD: let t = u.zoom_params.x + 0.001;

// BAD:  for (var i = 0; i < i32(u.zoom_params.z * 64.0); i++)  // can loop 0 times
// GOOD: for (var i = 0; i < max(i32(u.zoom_params.z * 64.0), 1); i++)
```

### Step 8 — Add mathematical depth

Each shader should gain at least one technique from the Algorithmist toolkit:

**For sorting shaders (bitonic-sort, luma-pixel-sort, pixel-depth-sort, scanline-sorting):**
- Add FBM-based comparison key that mixes luma with noise for organic sort order
- Vary sort axis direction by zoom_params (horizontal/vertical/diagonal/radial)
- Use depth to create a "depth sort" layer separate from color sort
- Audio-reactive sort threshold: `threshold = base + bass * 0.3`

**For distortion shaders (elastic-chromatic, scan-distort, digital-lens, spiral-lens, tile-twist):**
- Add Lissajous-based secondary displacement source
- Apply barrel/pincushion lens distortion: `r * (1 + k1*r² + k2*r⁴)`
- Use curl noise for organic warp contribution
- Spectral chromatic split across 3-5 wavelengths

**For retro-glitch shaders (waveform-glitch, phosphor-decay, crt-magnet, scanline-wave):**
- Add VHS head-switching band at bottom 5-10% of frame
- Use FBM for organic noise (replace simple hash where present)
- CRT shadow mask: modulate by sub-pixel grid `fract(uv * resolution / 3.0)`
- Bloom: accumulate luma-bright pixels with Gaussian kernel

**For temporal/artistic shaders (temporal-rgb-smear, chrono-slit-scan, echo-ripple):**
- Multi-tap temporal history using `dataTextureC` for previous frame
- Direction-aware smear using velocity estimated from mouse delta
- Temporal coherence: weight current vs history by luma difference

**For simulation shaders (pixel-sand, pixel-stretch-cross, page-curl-interactive):**
- Apply secondary force field based on curl noise
- Depth-aware displacement (deeper pixels displace less)
- Use Fibonacci disk sampling for better multi-sample quality

**For geometric shaders (quad-mirror, tesseract-fold, polar-warp-interactive, mosaic-reveal):**
- Add FBM domain warp to seam/edge regions for organic feel
- Animate tile parameters with sin waves based on time + zoom_params
- Fresnel-like edge glow at fold/mirror boundaries

**For interactive shaders (data-slicer-interactive, interactive-magnetic-ripple, polar-warp-interactive):**
- Use `u.ripples` array for multi-touch / multi-click ripple accumulation:
  ```wgsl
  var rippleDisp = vec2<f32>(0.0);
  for (var i = 0u; i < 50u; i++) {
      let r = u.ripples[i];
      if (r.w <= 0.0) { continue; }
      let age = u.config.x - r.z;
      let dist = length(uv - r.xy);
      let wave = sin(dist * 40.0 - age * 8.0) * exp(-age * 2.0) * r.w;
      rippleDisp += normalize(uv - r.xy + vec2<f32>(0.001)) * wave * 0.02;
  }
  ```

---

## Per-Shader Specific Upgrade Targets

### D1 — `bitonic-sort`
- Fix workgroup size.
- Sort key should blend luma + FBM noise: `key = luma * (1.0 - noiseMix) + fbm(uv*8.0, 3) * noiseMix`
- zoom_params: x=Sort Threshold, y=Noise Mix, z=Sort Direction (0=H,0.5=V,1=radial), w=Iterations
- Alpha: luminance-key on sorted output, preserving src.a in unsorted regions
- Bass → sort threshold modulation

### D2 — `temporal-rgb-smear`
- Fix workgroup size.
- Add directional smear using mouse velocity estimated as `mousePos - prevMousePos` (use `dataTextureC` to store prev position)
- zoom_params: x=Smear Length, y=Smear Decay, z=Chromatic Split, w=Turbulence
- Alpha: accumulative — trails fade over time, full alpha at mouse position
- Mids → chromatic split amount

### D3 — `elastic-chromatic`
- Fix workgroup size.
- Add Lissajous-based secondary chromatic source oscillating around mouse
- zoom_params: x=Elasticity, y=Chromatic Scale, z=Lissajous Ratio, w=Damping
- Alpha: effect-mask — stronger aberration = higher alpha at edges
- Bass → elastic spring constant

### D4 — `waveform-glitch`
- Fix workgroup size.
- Add VHS head-switching noise band at bottom 8% of frame:
  ```wgsl
  if (uv.y < 0.08) {
      let headNoise = hash11(uv.y * 1000.0 + time) * vhsIntensity;
      warped.x += headNoise * 0.05;
  }
  ```
- CRT shadow mask: `rgb *= 0.85 + 0.15 * step(0.33, fract(uv.x * resolution.x / 3.0))`
- zoom_params: x=Wave Intensity, y=VHS Intensity, z=Block Glitch Size, w=Shadow Mask
- Alpha: effect-mask based on glitch displacement magnitude
- Bass → wave intensity spike

### D5 — `data-slicer-interactive`
- Fix workgroup size.
- Use `u.ripples` array for click-triggered slice bursts
- Add FBM warp to slice edges for torn/organic look
- zoom_params: x=Slice Count, y=Slice Width, z=FBM Warp, w=Color Shift
- Alpha: preserves src.a, reduces alpha at slice boundaries
- Bass → slice count modulation

### D6 — `pixel-stretch-cross`
- Fix workgroup size.
- Add depth-aware stretch: pixels at greater depth stretch less
- Apply Fibonacci disk sampling for multi-direction stretch
- zoom_params: x=H Stretch, y=V Stretch, z=Depth Influence, w=Turbulence
- Alpha: effect-mask — high stretch = slight transparency
- Bass → stretch magnitude

### D7 — `interactive-magnetic-ripple`
- Fix workgroup size.
- Process all 50 ripple points from `u.ripples` for multi-click accumulation
- Add magnetic field lines using curl noise
- zoom_params: x=Ripple Frequency, y=Ripple Decay, z=Field Strength, w=Chromatic Split
- Alpha: preserves src.a, adds glow at high-intensity ripple peaks
- Bass → field strength pulse

### D8 — `luma-pixel-sort`
- Fix workgroup size.
- Add Fibonacci disk neighborhood sampling for quality
- Blend sorted and original using depth: far pixels = more sorted
- zoom_params: x=Luma Threshold, y=Sort Length, z=Depth Blend, w=Noise Mix
- Alpha: luminance-key — bright sorted segments are more opaque
- Treble → threshold modulation

### D9 — `pixel-depth-sort`
- Fix workgroup size.
- Sort direction should follow mouse position (sort toward/away from mouse)
- Add chromatic aberration at sort boundaries
- zoom_params: x=Depth Threshold, y=Sort Length, z=Sort Angle, w=Aberration
- Alpha: depth-layered — near pixels more opaque
- Bass → sort length extension

### D10 — `pixel-sand`
- Fix workgroup size.
- Apply curl noise secondary force field
- Add height-field: bright pixels are "heavier" and fall faster
- zoom_params: x=Gravity, y=Particle Density, z=Curl Force, w=Bounce
- Alpha: proportional to sand particle presence (dark = transparent)
- Bass → gravity pulse

### D11 — `phosphor-decay`
- Fix workgroup size.
- Add per-channel phosphor decay rates (R decays fastest, B slowest — real CRT behavior):
  ```wgsl
  let decayR = 0.95 - u.zoom_params.x * 0.1;
  let decayG = 0.96 - u.zoom_params.x * 0.1;
  let decayB = 0.98 - u.zoom_params.x * 0.05;
  ```
- CRT shadow mask and scan-line blanking
- zoom_params: x=Decay Rate, y=Bloom Spread, z=Shadow Mask Strength, w=Scan Blanking
- Alpha: luminance-key — phosphor glow is additive, dark = transparent
- Bass → bloom burst on beat

### D12 — `crt-magnet`
- Fix workgroup size.
- Add color bloom: extract high-luma pixels, blur with Gaussian kernel, add back
- Simulate degaussing distortion near mouse with radial magnetic field
- zoom_params: x=Magnet Strength, y=Bloom Intensity, z=Color Shift, w=Distortion Radius
- Alpha: luminance-key — bloom areas are bright/opaque, dark = transparent
- Bass → magnet pulse strength

### D13 — `scan-distort-gpt52`
- Fix workgroup size.
- Split into 3 frequency bands (low/mid/high luma) and apply different distortions per band
- Add FBM to scan line positions
- zoom_params: x=Scan Intensity, y=Band Split, z=FBM Scale, w=Chromatic Mix
- Alpha: effect-mask
- Mids → band distortion amount

### D14 — `digital-lens`
- Fix workgroup size.
- Implement proper barrel/pincushion lens distortion model:
  `r_distorted = r * (1.0 + k1*r*r + k2*r*r*r*r)` where k1 is from zoom_params
- Add spectral chromatic dispersion (3-sample RGB split)
- zoom_params: x=Distortion (k1), y=Dispersion, z=Vignette, w=Focus Point
- Alpha: lens transmission — vignette darkens + alpha reduces at edges
- Bass → distortion pulse

### D15 — `chromatic-mosaic-projector`
- Fix workgroup size.
- Add animated Voronoi cell distortion to mosaic boundaries
- Per-cell chromatic shift based on cell hash
- zoom_params: x=Cell Size, y=Chromatic Strength, z=Voronoi Distort, w=Projection Angle
- Alpha: preserves src.a, smooth cell boundary transitions
- Bass → cell size pulse

### D16 — `chrono-slit-scan`
- Fix workgroup size.
- Add multi-slit: 2–3 simultaneous animated slits using sin waves
- Feather slit edges with smoothstep
- zoom_params: x=Slit Count, y=Slit Width, z=Slit Speed, w=Feather
- Alpha: slit-age based — freshly scanned regions more opaque
- Mids → slit speed modulation

### D17 — `mosaic-reveal`
- Fix workgroup size.
- Hexagonal grid option (toggle via zoom_params.w threshold):
  ```wgsl
  // Hex grid: use axial coordinate system
  let q = (2.0/3.0) * p.x / hexSize;
  let r = (-1.0/3.0 * p.x + sqrt(3.0)/3.0 * p.y) / hexSize;
  ```
- Add flood-fill reveal animation from mouse position
- zoom_params: x=Cell Size, y=Reveal Speed, z=Edge Glow, w=Grid Type (0=square, 1=hex)
- Alpha: reveal-mask based — revealed cells are opaque, others fade
- Bass → reveal pulse

### D18 — `quad-mirror`
- Fix workgroup size.
- Add FBM domain warp at seam boundaries (±5% around mirror lines) for organic feel
- Animate mirror rotation with time + zoom_params
- zoom_params: x=H Mirror Offset, y=V Mirror Offset, z=Seam Warp, w=Rotation
- Alpha: preserves src.a, reduces at seams proportional to warp amount
- Treble → seam warp shimmer

### D19 — `spiral-lens`
- Fix workgroup size.
- Implement Archimedean spiral UV unwrap: `theta = atan2(p.y, p.x), r = length(p), uv_spiral = (theta/(2pi), r)`
- Add chromatic dispersion along spiral radius
- zoom_params: x=Spiral Tightness, y=Lens Strength, z=Chromatic, w=Rotation Speed
- Alpha: depth-layered — center of spiral more opaque
- Bass → lens strength pulse

### D20 — `tile-twist`
- Fix workgroup size.
- Apply Lissajous oscillation to tile rotation angles
- Each tile's twist amount proportional to hash(tile_id) * zoom_params
- zoom_params: x=Twist Angle, y=Tile Size, z=Lissajous Ratio, w=Turbulence
- Alpha: preserves src.a, reduces at tile edges with smoothstep
- Mids → oscillation speed

### D21 — `page-curl-interactive`
- Fix workgroup size.
- Physically correct page curl: UV transform using cylindrical projection around curl axis
- Add paper texture using FBM on the revealed back face
- zoom_params: x=Curl Angle, y=Curl Radius, z=Paper Texture, w=Shadow Intensity
- Alpha: curl shadow reduces alpha at fold line
- Bass → curl snap on beat

### D22 — `tesseract-fold`
- Fix workgroup size.
- Implement proper 4D→2D projection: rotate w-axis by time, project onto xy plane
- Add edge glow at 4D fold boundaries using smoothstep SDF
- zoom_params: x=4D Rotation Speed, y=Projection Scale, z=Edge Glow Width, w=Face Opacity
- Alpha: face opacity from zoom_params.w, edges brighter
- Treble → edge glow pulse

### D23 — `polar-warp-interactive`
- Fix workgroup size.
- Use `u.ripples` for click-triggered polar distortion bursts
- Add spiral component: `theta += spiralStrength * r`
- zoom_params: x=Warp Strength, y=Spiral Amount, z=Ripple Decay, w=Pinch/Expand
- Alpha: preserves src.a, reduces at extreme warp distortion
- Bass → warp strength pulse

### D24 — `echo-ripple`
- Fix workgroup size.
- Accumulate ring echoes in `dataTextureA` with configurable decay
- Multi-ripple from `u.ripples` array
- zoom_params: x=Ring Frequency, y=Ring Decay, z=Echo Layers, w=Color Tint
- Alpha: ring intensity drives alpha — bright rings opaque, gaps transparent
- Mids → ring frequency modulation

### D25 — `scanline-wave`
- Fix workgroup size.
- Add per-scanline phase offset using FBM for organic wave (not pure sine)
- CRT shadow mask: `0.85 + 0.15 * step(0.5, fract(coord.y * 0.5))`
- Add scan blanking: every N-th line slightly darker
- zoom_params: x=Wave Amplitude, y=Wave Frequency, z=FBM Amount, w=Scanline Strength
- Alpha: scanline gaps are slightly transparent
- Bass → wave amplitude pulse

---

## JSON Definition Updates

After upgrading each shader, update (or create) its JSON definition in `shader_definitions/<category>/<id>.json`:

```json
{
  "id": "<shader-id>",
  "name": "<Display Name>",
  "url": "shaders/<id>.wgsl",
  "category": "<category>",
  "description": "<1-sentence description of the upgraded effect>",
  "features": ["upgraded-rgba", "depth-aware", "audio-reactive", "mouse-driven"],
  "params": [
    { "id": "param1", "name": "<Param1 Name>", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01 },
    { "id": "param2", "name": "<Param2 Name>", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01 },
    { "id": "param3", "name": "<Param3 Name>", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01 },
    { "id": "param4", "name": "<Param4 Name>", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01 }
  ]
}
```

**Required `features` tags:**
- `"upgraded-rgba"` — always add after RGBA upgrade
- `"depth-aware"` — add if writeDepthTexture is written meaningfully
- `"audio-reactive"` — add if plasmaBuffer is used
- `"mouse-driven"` — add if zoom_config.yz (mouse position) drives the effect
- `"temporal-feedback"` — add if dataTextureC (previous frame) is read
- `"multi-ripple"` — add if u.ripples array is processed

---

## QA Checklist

Run this check for every shader before marking complete:

```
[ ] @workgroup_size(8, 8, 1) — NOT (16,16,1)
[ ] Bounds check present: if (id.x >= res.x || id.y >= res.y) { return; }
[ ] Full 13-binding header present
[ ] struct Uniforms has ripples: array<vec4<f32>, 50>
[ ] textureStore(writeTexture, ...) called with vec4<f32>(rgb, alpha)
[ ] textureStore(writeDepthTexture, ...) called
[ ] Alpha is NOT hardcoded to 1.0
[ ] plasmaBuffer[0].x/y/z used for at least one visual effect
[ ] All 4 zoom_params.x/y/z/w are used
[ ] All params produce non-black output at 0.0 and 1.0
[ ] No division by zero (epsilon added where needed)
[ ] JSON definition updated with all 4 params and feature tags
[ ] node scripts/generate_shader_lists.js runs without errors
```

---

## Execution Order

Work D1 → D25 in sequence. After each shader:
1. Write the upgraded WGSL.
2. Update/create the JSON definition.
3. Verify with `node scripts/generate_shader_lists.js`.
4. Mark complete in this file by replacing `D#` with `✅ D#`.

**Start with D1 (`bitonic-sort`) as the pilot to validate the pattern, then continue.**
