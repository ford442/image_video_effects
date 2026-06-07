# WGSL Built-ins & Patterns Reference for Generative Shaders

> **Audience**: Swarm agents writing or upgrading generative shaders for Pixelocity.  
> **Rule**: Every function here is valid in a `@compute` shader. Functions marked ⛔ are fragment-only and will cause a naga validation error in compute.

---

## 0. Canonical 13-Binding Header

Copy this verbatim — do not invent bindings, rename them, or reorder them.

```wgsl
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
  config: vec4<f32>,       // .x = time, .y = delta_time, .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = zoom, .yz = mouse_uv (0-1), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // .xyzw = user params p1…p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = time_created, .w = strength
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;
```

**Accessing audio** (always use these three):
```wgsl
let bass   = plasmaBuffer[0].x;  // 20–200 Hz energy,   range ~0–2
let mids   = plasmaBuffer[0].y;  // 200–2000 Hz energy, range ~0–2
let treble = plasmaBuffer[0].z;  // 2k–20k Hz energy,   range ~0–2
```

**Entry point** — always exactly:
```wgsl
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    // bounds guard — mandatory
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    ...
}
```

---

## 1. Math Built-ins

All operate on `f32`, `vec2<f32>`, `vec3<f32>`, `vec4<f32>` unless noted.

### Rounding & Range

| Function | Signature | Notes |
|----------|-----------|-------|
| `abs(x)` | `T → T` | Component-wise |
| `sign(x)` | `T → T` | -1, 0, or 1 |
| `floor(x)` | `T → T` | Round toward -∞ |
| `ceil(x)` | `T → T` | Round toward +∞ |
| `round(x)` | `T → T` | Round to nearest (ties → even) |
| `fract(x)` | `T → T` | `x - floor(x)` |
| `trunc(x)` | `T → T` | Round toward 0 |
| `clamp(x, lo, hi)` | `T,T,T → T` | Clamp to `[lo, hi]` |
| `saturate(x)` | `T → T` | Clamp to `[0, 1]` — WGSL shorthand |
| `min(a, b)` | `T,T → T` | Component-wise |
| `max(a, b)` | `T,T → T` | Component-wise |

### Interpolation & Smoothing

```wgsl
mix(a, b, t)          // Linear lerp:  a + t*(b-a)
step(edge, x)         // 0.0 if x < edge, else 1.0
smoothstep(lo, hi, x) // Hermite 3t²-2t³ between lo and hi
```

**`select` — branchless conditional (prefer over if/else in hot paths)**:
```wgsl
select(false_val, true_val, condition)
// e.g.:
let v = select(0.0, 1.0, x > 0.5);      // f32
let c = select(vec3(0.0), col, hit);     // vec3<f32>
```

### Exponential & Power

| Function | Notes |
|----------|-------|
| `sqrt(x)` | |
| `pow(x, e)` | Both must be `f32` or same vector type; `e` must be ≥ 0 for `f32` |
| `exp(x)` | eˣ |
| `exp2(x)` | 2ˣ |
| `log(x)` | ln(x) — returns -inf for x≤0, use with care |
| `log2(x)` | |

### Trigonometry

| Function | Range | Notes |
|----------|-------|-------|
| `sin(x)` | -1…1 | Radians |
| `cos(x)` | -1…1 | Radians |
| `tan(x)` | — | **Not in WGSL spec** — use `sin(x)/cos(x)` |
| `asin(x)` | -π/2…π/2 | |
| `acos(x)` | 0…π | |
| `atan(x)` | -π/2…π/2 | 1-arg form |
| `atan2(y, x)` | -π…π | **2-arg form** — use this for angles from vectors |
| `sinh`, `cosh`, `tanh` | — | Available in WGSL 1.0 |

> ⚠️ `tan()` does not exist in WGSL. Use `sin(x) / cos(x)`.  
> ⚠️ Use `atan2(y, x)` not `atan(y/x)` — avoids division by zero and handles all quadrants.

---

## 2. Geometry Built-ins

```wgsl
length(v)             // Euclidean length of vector
distance(a, b)        // length(b - a)
normalize(v)          // v / length(v) — undefined if length is 0
dot(a, b)             // Dot product — scalar
cross(a, b)           // Cross product — vec3 only
reflect(i, n)         // Reflect incident i around normal n
refract(i, n, eta)    // Snell's law refraction
```

**UV centering patterns**:
```wgsl
// Center UV at (0,0) with aspect ratio preserved
let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);

// Normalized 0-1 UV
let uv = vec2<f32>(pixel) / res;
```

---

## 3. Texture Functions in Compute

⛔ `textureSample` — **fragment-only, will fail in compute**  
✅ Use these instead:

```wgsl
// Read from texture at integer pixel coords (no filtering)
textureLoad(readTexture, pixel, 0)           // returns vec4<f32>
textureLoad(readDepthTexture, pixel, 0).r    // depth scalar
textureLoad(dataTextureC, pixel, 0)          // previous frame state

// Read with UV coords (bilinear filtering)
textureSampleLevel(readTexture, u_sampler, uv, 0.0)

// Write to storage texture
textureStore(writeTexture, pixel, vec4<f32>(color, alpha))
textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0))
textureStore(dataTextureA, pixel, vec4<f32>(...))   // writeable data channel A
textureStore(dataTextureB, pixel, vec4<f32>(...))   // writeable data channel B

// Get texture dimensions
let dims = vec2<f32>(textureDimensions(readTexture));
```

⛔ `dpdx`, `dpdy` — **fragment-only derivatives, not available in compute**

---

## 4. Standard Hash & Noise Library

These are the **canonical forms used across the codebase**. Copy exactly — swarm agents that deviate (e.g. different constants) produce different noise character and fail cross-shader blending.

```wgsl
// ── Hashes ─────────────────────────────────────────────────────
fn hashf(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453);
}
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}
fn hash2f(n: f32) -> vec2<f32> {
    return vec2<f32>(hashf(n), hashf(n + 73.156));
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(hash21(p), hash21(p + vec2<f32>(17.0, 31.0)));
}

// ── Value Noise ─────────────────────────────────────────────────
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);  // smoothstep
    return mix(
        mix(hash21(i),                  hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// ── fBM (Fractional Brownian Motion) ────────────────────────────
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0; var amp = 0.5; var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        sum  += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp  *= 0.5;
    }
    return sum;
}

// ── Domain Warp (feed fBM back into fBM for organic flow) ────────
fn domainWarp(p: vec2<f32>, strength: f32, octaves: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, octaves), fbm(p + vec2<f32>(5.2, 1.3), octaves));
    return p + strength * q;
}
```

**Octave guidelines** — stay within budget:
| Octaves | Use case | Cost |
|---------|----------|------|
| 2–3 | Fast motion fields, audio-reactive pulses | Cheap |
| 4–5 | General terrain, organic shapes | Moderate |
| 6–8 | High-quality landscapes, volumetric noise | Expensive |
| 10+ | Only with distance-based LOD gating | Very expensive |

---

## 5. Color Utilities

### ACES Tone Mapping — **required on all modern shaders**

```wgsl
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
// Usage: color = acesToneMap(color * exposure);
```

### HSV ↔ RGB

```wgsl
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let c = hsv.z * hsv.y;
    let h = hsv.x * 6.0;
    let x = c * (1.0 - abs(fract(h / 2.0) * 2.0 - 1.0));
    let m = hsv.z - c;
    var rgb: vec3<f32>;
    if      (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else              { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(m);
}

fn rgb2hsv(rgb: vec3<f32>) -> vec3<f32> {
    let mx = max(max(rgb.r, rgb.g), rgb.b);
    let mn = min(min(rgb.r, rgb.g), rgb.b);
    let d  = mx - mn;
    var h  = 0.0;
    if d > 0.0 {
        if      mx == rgb.r { h = (rgb.g - rgb.b) / d + select(0.0, 6.0, rgb.g < rgb.b); }
        else if mx == rgb.g { h = (rgb.b - rgb.r) / d + 2.0; }
        else                { h = (rgb.r - rgb.g) / d + 4.0; }
        h /= 6.0;
    }
    return vec3<f32>(h, select(0.0, d / mx, mx > 0.0), mx);
}
```

### YUV ↔ RGB (VHS/chroma noise)

```wgsl
fn rgbToYuv(rgb: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(
         0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b,
        -0.14713 * rgb.r - 0.28886 * rgb.g + 0.436 * rgb.b,
         0.615 * rgb.r - 0.51499 * rgb.g - 0.10001 * rgb.b
    );
}
fn yuvToRgb(yuv: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(
        yuv.x + 1.13983 * yuv.z,
        yuv.x - 0.39465 * yuv.y - 0.58060 * yuv.z,
        yuv.x + 2.03211 * yuv.y
    );
}
```

### Luma

```wgsl
fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}
```

### Heat Map Palette

```wgsl
fn heatColor(t: f32) -> vec3<f32> {
    // t: 0–1, black→blue→cyan→yellow→red→white
    let stops = array<vec3<f32>, 5>(
        vec3<f32>(0.05, 0.15, 0.55),
        vec3<f32>(0.15, 0.65, 0.85),
        vec3<f32>(0.85, 0.75, 0.15),
        vec3<f32>(0.85, 0.25, 0.10),
        vec3<f32>(0.95, 0.95, 0.90)
    );
    let idx = clamp(t, 0.0, 1.0) * 4.0;
    let i   = i32(clamp(idx, 0.0, 3.0));
    return mix(stops[i], stops[i + 1], fract(idx));
}
```

### Psychedelic Utilities

Use these for Batch 4 color/movement upgrades. They are compute-safe, Naga-safe, and avoid unbounded loops. `psychedelicPalette`, `neonGlow`, `organicDrift`, and `pulseScale` add no bindings. `chromaticAberration` uses the existing canonical `readTexture`/`u_sampler` bindings.

```wgsl
// Usage:
// let raw = psychedelicPalette(u.config.x * 0.08 + u.zoom_params.x);
// let color = mix(vec3<f32>(dot(raw, vec3<f32>(0.2126, 0.7152, 0.0722))), raw, clamp(u.zoom_params.y, 0.0, 1.0));
fn psychedelicPalette(t: f32) -> vec3<f32> {
    let hue = fract(t);
    let saturation = clamp(0.72 + 0.28 * sin(TAU * (t * 0.137 + 0.19)), 0.45, 1.0);
    let value = 1.0 + 0.18 * sin(TAU * (t * 0.071 + 0.43));
    let rgb = clamp(abs(fract(vec3<f32>(hue) + vec3<f32>(0.0, 0.6666667, 0.3333333)) * 6.0 - vec3<f32>(3.0)) - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0));
    let smoothRgb = rgb * rgb * (vec3<f32>(3.0) - 2.0 * rgb);
    return mix(vec3<f32>(value), smoothRgb * value, saturation);
}

// Usage:
// color = neonGlow(color, 0.35 + plasmaBuffer[0].z * 0.2);
fn neonGlow(color: vec3<f32>, intensity: f32) -> vec3<f32> {
    let safeColor = max(color, vec3<f32>(0.0));
    let lum = dot(safeColor, vec3<f32>(0.2126, 0.7152, 0.0722));
    let glowMask = smoothstep(0.22, 1.0, lum);
    let chroma = normalize(safeColor + vec3<f32>(0.001)) * max(lum, 0.18);
    let bloom = (safeColor * safeColor + chroma) * glowMask * max(intensity, 0.0);
    return safeColor + bloom;
}

// Usage:
// let driftedUv = uv + organicDrift(uv, u.config.x, 8.0) * 0.05;
fn organicDrift(uv: vec2<f32>, time: f32, scale: f32) -> vec2<f32> {
    let safeScale = max(scale, 0.001);
    let p = uv * safeScale;
    let slow = vec2<f32>(time * 0.11, -time * 0.08);
    let q = vec2<f32>(
        fbm(p + slow, 3),
        fbm(p * 1.37 + vec2<f32>(5.2, 1.3) - slow.yx, 3)
    );
    let r = vec2<f32>(
        fbm(p * 0.73 + q * 2.0 + vec2<f32>(1.7, 9.2), 2),
        fbm(p * 0.91 - q.yx * 2.0 + vec2<f32>(8.1, 2.8), 2)
    );
    return ((q + r * 0.5) * 2.0 - vec2<f32>(1.5)) / safeScale;
}

// Usage:
// let breathing = pulseScale(u.config.x, 1.25 + plasmaBuffer[0].x);
fn pulseScale(time: f32, speed: f32) -> f32 {
    let wave = 0.5 + 0.5 * sin(time * speed);
    return 0.8 + smoothstep(0.0, 1.0, wave) * 0.4;
}

// Usage:
// let ca = chromaticAberration(uv01, 0.003 + readDepth * 0.002);
fn chromaticAberration(uv: vec2<f32>, amount: f32) -> vec3<f32> {
    let center = vec2<f32>(0.5);
    let delta = uv - center;
    let lenSq = max(dot(delta, delta), 0.000001);
    let dir = delta * inverseSqrt(lenSq);
    let offset = dir * max(amount, 0.0);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + offset, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - offset * 0.6, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    return vec3<f32>(r, g, b);
}
```

**Batch 4 usage pattern**:
```wgsl
let drift = organicDrift(uv01, time, 8.0) * (0.05 + bass * 0.03);
let p = uv + drift;
var color = psychedelicPalette(fbm(p * 3.0, 4) + time * 0.08 + u.zoom_params.x);
color = mix(vec3<f32>(dot(color, vec3<f32>(0.2126, 0.7152, 0.0722))), color, clamp(u.zoom_params.y, 0.0, 1.0));
color = neonGlow(color, 0.4 + mids * 0.25);
color *= pulseScale(time, 1.5 + bass);
color = acesToneMap(color * 1.1);
```

---

## 6. SDF Primitives (2D & 3D)

These are the building blocks for generative geometry. All return a signed distance (negative = inside).

### 2D

```wgsl
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
    return length(p) - r;
}
fn sdBox2(p: vec2<f32>, b: vec2<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}
fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a; let ba = b - a;
    let h  = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}
fn sdEquilTri(p: vec2<f32>, r: f32) -> f32 {
    let k = sqrt(3.0);
    var q = vec2<f32>(abs(p.x) - r, p.y + r / k);
    if q.x + k * q.y > 0.0 { q = vec2<f32>(q.x - k * q.y, -k * q.x - q.y) / 2.0; }
    q.x -= clamp(q.x, -2.0 * r, 0.0);
    return -length(q) * sign(q.y);
}
fn sdHexagon(p: vec2<f32>, r: f32) -> f32 {
    let k = vec3<f32>(-0.866025404, 0.5, 0.577350269);
    var q = abs(p);
    q -= 2.0 * min(dot(k.xy, q), 0.0) * k.xy;
    q -= vec2<f32>(clamp(q.x, -k.z * r, k.z * r), r);
    return length(q) * sign(q.y);
}
```

### 3D

```wgsl
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}
fn sdBox3(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a; let ba = b - a;
    let h  = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}
```

### Smooth Boolean Ops

```wgsl
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
fn smax(a: f32, b: f32, k: f32) -> f32 { return -smin(-a, -b, k); }

// Domain repetition (tile a shape infinitely)
fn opRep(p: vec3<f32>, spacing: vec3<f32>) -> vec3<f32> {
    return p - spacing * round(p / spacing);
}
```

---

## 7. Rotation Helpers

```wgsl
fn rot2(angle: f32) -> mat2x2<f32> {
    let c = cos(angle); let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// Apply 2D rotation: new_pos = rot2(angle) * pos
// In WGSL: let p2 = rot2(angle) * vec2<f32>(x, y);

fn rotX(v: vec3<f32>, a: f32) -> vec3<f32> {
    let c = cos(a); let s = sin(a);
    return vec3<f32>(v.x, c * v.y - s * v.z, s * v.y + c * v.z);
}
fn rotY(v: vec3<f32>, a: f32) -> vec3<f32> {
    let c = cos(a); let s = sin(a);
    return vec3<f32>(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
}
fn rotZ(v: vec3<f32>, a: f32) -> vec3<f32> {
    let c = cos(a); let s = sin(a);
    return vec3<f32>(c * v.x - s * v.y, s * v.x + c * v.y, v.z);
}
```

---

## 8. Chromatic Aberration (required for modern shaders)

```wgsl
// For texture-backed shaders, use chromaticAberration(uv, amount) from
// "Psychedelic Utilities" above.

// For generative shaders (no readTexture) — separate hue channels
fn genChromaticShift(color: vec3<f32>, uv: vec2<f32>, strength: f32, time: f32) -> vec3<f32> {
    let angle = atan2(uv.y - 0.5, uv.x - 0.5);
    let shift  = vec2<f32>(cos(angle), sin(angle)) * strength;
    // Slightly shift R and B UV, keep G as reference
    return vec3<f32>(
        color.r * (1.0 + shift.x * 0.8),
        color.g,
        color.b * (1.0 - shift.y * 0.5)
    );
}
```

**When to use**: Apply as the last color transform before `acesToneMap`. Strength should be scaled by `bass` or `depth` for reactivity:
```wgsl
let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
color = genChromaticShift(color, uv_01, caStr, time);
color = acesToneMap(color * 1.1);
```

---

## 9. Temporal Feedback Patterns

### Decay / trail

```wgsl
let prev  = textureLoad(dataTextureC, pixel, 0);
let decay = 0.97 - p4 * 0.03;           // p4 slider controls trail length
let next  = mix(prev, newColor, 0.15);   // blend toward new frame
textureStore(dataTextureA, pixel, vec4<f32>(next.rgb * decay, next.a));
```

### Monte Carlo accumulation

```wgsl
let prev  = textureLoad(dataTextureC, pixel, 0);
let n     = prev.a;                       // sample count stored in alpha
let accum = (prev.rgb * n + newSample) / (n + 1.0);
textureStore(dataTextureA, pixel, vec4<f32>(accum, min(n + 1.0, 256.0)));
```

### Reset on mouse click

```wgsl
let mouseDown = u.zoom_config.w > 0.5;
let resetMask = f32(mouseDown && n > 200.0);
let writeColor = mix(accum, newSample, resetMask);
```

---

## 10. Semantic Alpha Rules

**Never write `vec4<f32>(color, 1.0)` unless the shader is opaque by design.**

| Alpha meaning | Use case | Example |
|---------------|----------|---------|
| `intensity` | Glow / particle density | `alpha = clamp(count * 0.1, 0.0, 1.0)` |
| `depth` | Compositing with background | `alpha = 1.0 - depth * 0.4` |
| `heat` | Simulation field strength | `alpha = clamp(heat * 0.08, 0.0, 0.9)` |
| `1.0` | Fully opaque post-process | Only for final-pass effects |
| `0.0` | Transparent (no contribution) | On empty/background pixels |

---

## 11. Common Anti-Patterns (Causes of Naga Errors)

| Wrong | Correct | Why |
|-------|---------|-----|
| `tan(x)` | `sin(x) / cos(x)` | `tan` not in WGSL spec |
| `textureSample(...)` | `textureSampleLevel(..., 0.0)` | `textureSample` requires fragment stage |
| `dpdx(x)` | remove or compute finite diff | Fragment-only derivative |
| `var x = 1` | `var x: i32 = 1` or `var x = 1i` | Type inference can fail with plain int literal |
| `array<f32, n>` where n is runtime | `array<f32, 8>` | Array size must be const in WGSL |
| Nested `for` > 4 levels with texture reads | Flatten or reduce loops | GPU timeout / TDR |
| Writing same pixel from multiple threads | Use `textureStore` once per thread per output | Race condition |
| `outputTex`, `iTime`, `mouse` | Canonical names above | Engine will not bind unknown names |

---

## 12. Generative Shader Template (150–180 lines)

Minimal fully-featured generative shader with all modern upgrades. Expand from here.

```wgsl
// ═══ [SHADER NAME] ═══════════════════════════════════════════════
//  Category: generative
//  Features: [list], audio-reactive, depth-aware, temporal-feedback,
//             aces-tone-map, chromatic-aberration, semantic-alpha
//  Complexity: Medium

// [paste canonical 13-binding header here]

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

// ── Core math ───────────────────────────────────────────────────
fn hashf(n: f32) -> f32 { return fract(sin(n * 127.1) * 43758.5453); }
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i+vec2(1,0)), u.x),
               mix(hash21(i+vec2(0,1)), hash21(i+vec2(1,1)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s=0.0; var a=0.5; var f=1.0;
    for (var i=0;i<oct;i++) { s+=a*valueNoise(p*f); f*=2.0; a*=0.5; }
    return s;
}

// ── Tone map ────────────────────────────────────────────────────
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x*(2.51*x+0.03))/(x*(2.43*x+0.59)+0.14), vec3(0.0), vec3(1.0));
}

// ── [Effect-specific functions here] ────────────────────────────

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv01  = vec2<f32>(pixel) / res;
    let uv    = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time  = u.config.x;
    let mouse = u.zoom_config.yz;
    let p1    = u.zoom_params.x;
    let p2    = u.zoom_params.y;
    let p3    = u.zoom_params.z;
    let p4    = u.zoom_params.w;

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth  = textureLoad(readDepthTexture, pixel, 0).r;
    let prev   = textureLoad(dataTextureC, pixel, 0);

    // ── Effect computation ─────────────────────────────────────
    var color = vec3<f32>(0.0);
    // ... your code here ...

    // ── Temporal feedback ──────────────────────────────────────
    let decay = 0.97 - p4 * 0.02;
    let trail = mix(prev.rgb * decay, color, 0.2 + bass * 0.1);
    textureStore(dataTextureA, pixel, vec4<f32>(trail, prev.a));

    // ── Chromatic aberration ───────────────────────────────────
    let caStr = 0.003 * (1.0 + bass) + depth * 0.001;
    let dir   = normalize(uv01 - vec2<f32>(0.5) + vec2<f32>(0.001));
    color = vec3<f32>(
        color.r + dir.x * caStr,
        color.g,
        color.b - dir.y * caStr * 0.5
    );

    // ── ACES + semantic alpha ──────────────────────────────────
    color = acesToneMap(color * (0.9 + mids * 0.2));
    let alpha = clamp(luma(color) * 1.5, 0.2, 0.95) * (0.7 + depth * 0.3);
    textureStore(writeTexture, pixel, vec4<f32>(color, alpha));
}
```

---

## 13. Quick Reference Card

```
MUST USE in compute:
  textureSampleLevel(tex, sampler, uv, 0.0)
  textureLoad(tex, pixel_i32, 0)
  textureStore(storageTex, pixel_i32, value)

NEVER USE in compute:
  textureSample(...)     → fragment only
  dpdx / dpdy            → fragment only
  tan(x)                 → not in WGSL

BRANCHLESS PREFERENCE:
  select(a, b, cond)     → instead of if/else for simple values
  mix(a, b, f32(cond))   → smooth blend controlled by bool
  step(edge, x)          → 0/1 threshold without branch

AUDIO DRIVES EVERYTHING:
  bass   = plasmaBuffer[0].x   → beat, punch, low energy
  mids   = plasmaBuffer[0].y   → melody, harmonic content
  treble = plasmaBuffer[0].z   → shimmer, high detail

ALPHA ENCODES MEANING:
  Never hardcode 1.0 — use intensity, density, or depth
```
