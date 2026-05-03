# Shader Upgrade Swarm - Technical Reference

Quick reference for agents working on shader upgrades.

---

## Mathematical Constants

```wgsl
const PI     = 3.14159265358979323846;
const TAU    = 6.28318530717958647692;
const PHI    = 1.61803398874989484820;   // golden ratio
const SQRT2  = 1.41421356237309504880;
const SQRT3  = 1.73205080756887729352;
const LN2    = 0.69314718055994530941;
const INV_PI = 0.31830988618379067154;
```

**Rule:** Replace all magic numbers with these constants. `6.28318` → `TAU`, `3.14159` → `PI`, `0.618` → `1.0/PHI`.

---

## RGB → RGBA Upgrade Patterns

### Pattern 1: Simple Alpha from Luminance

```wgsl
// BEFORE (RGB only):
let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
let processed = color * 2.0; // some processing
textureStore(writeTexture, coord, vec4<f32>(processed, 1.0));

// AFTER (RGBA with luminance alpha):
let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
let processed = color * 2.0;

// Alpha based on luminance (brighter = more opaque)
let luma = dot(processed, vec3<f32>(0.299, 0.587, 0.114));
let alpha = mix(0.5, 1.0, luma);

// Depth-aware enhancement
let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
alpha = alpha * mix(0.7, 1.0, depth);

textureStore(writeTexture, coord, vec4<f32>(processed, alpha));
textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
```

### Pattern 2: Edge-Preserve Alpha

```wgsl
// Detect edges using depth or color gradient
let depthR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(pixel.x, 0.0), 0.0).r;
let depthL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(pixel.x, 0.0), 0.0).r;
let depthU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, pixel.y), 0.0).r;
let depthD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, pixel.y), 0.0).r;

let edge = length(vec2<f32>(depthR - depthL, depthU - depthD));
let edgeMask = smoothstep(0.01, 0.1, edge);

// Edges are fully opaque, smooth areas can be transparent
let alpha = mix(0.6, 1.0, edgeMask);
```

### Pattern 3: Effect-Intensity Alpha

```wgsl
// For distortion effects - transparent where no effect
let effectStrength = someCalculation(uv);
let alpha = mix(0.3, 1.0, effectStrength);

// Optional: Fade to transparent at screen edges
let edgeFade = smoothstep(0.0, 0.1, uv.x) * smoothstep(1.0, 0.9, uv.x) *
               smoothstep(0.0, 0.1, uv.y) * smoothstep(1.0, 0.9, uv.y);
alpha = alpha * edgeFade;
```

---

## Randomization-Safe Parameter Patterns

### ✅ SAFE: Normalized Intensity

```wgsl
let intensity = u.zoom_params.x; // 0.0 to 1.0
let effect = base * (0.1 + intensity * 2.0); // Always valid
```

### ✅ SAFE: Blend Factor

```wgsl
let blend = u.zoom_params.y; // 0.0 to 1.0
let result = mix(colorA, colorB, blend); // Always valid
```

### ✅ SAFE: Frequency with Minimum

```wgsl
let frequency = mix(1.0, 10.0, u.zoom_params.z); // Never 0
```

### ❌ UNSAFE: Division by Param

```wgsl
// DANGEROUS - can divide by zero!
let scale = 1.0 / u.zoom_params.x;

// FIXED:
let scale = 1.0 / (u.zoom_params.x + 0.001);
```

### ❌ UNSAFE: Log of Param

```wgsl
// DANGEROUS - log(0) is undefined!
let val = log(u.zoom_params.w);

// FIXED:
let val = log(u.zoom_params.w + 0.001);
// OR:
let val = log(max(u.zoom_params.w, 0.001));
```

### ❌ UNSAFE: Pow with Variable Exponent

```wgsl
// DANGEROUS - negative base with fractional exponent!
let val = pow(someValue, u.zoom_params.x);

// FIXED - ensure positive base:
let val = pow(abs(someValue) + 0.001, u.zoom_params.x);
```

---

## Reusable Shader Chunks Library

### Noise Functions

```wgsl
// Hash functions
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash13(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Value noise
fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// FBM (Fractal Brownian Motion)
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var pp = p;
    for (var i = 0; i < octaves; i++) {
        v += a * vnoise(pp);
        pp = pp * 2.0 + vec2<f32>(100.0);
        a *= 0.5;
    }
    return v;
}

// Domain warping
fn domainWarp(p: vec2<f32>, time: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, 0.0), 4), fbm(p + vec2<f32>(5.2, 1.3), 4));
    let r = vec2<f32>(fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2) + time * 0.15, 4),
                      fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8) + time * 0.126, 4));
    return p + 4.0 * r;
}
```

### Color Utilities

```wgsl
// HSL to RGB conversion
fn hsl2rgb(h: f32, s: f32, l: f32) -> vec3<f32> {
    let c = (1.0 - abs(2.0 * l - 1.0)) * s;
    let x = c * (1.0 - abs((h * 6.0) % 2.0 - 1.0));
    let m = l - c / 2.0;
    
    var r = 0.0; var g = 0.0; var b = 0.0;
    if (h < 1.0/6.0) { r = c; g = x; }
    else if (h < 2.0/6.0) { r = x; g = c; }
    else if (h < 3.0/6.0) { g = c; b = x; }
    else if (h < 4.0/6.0) { g = x; b = c; }
    else if (h < 5.0/6.0) { r = x; b = c; }
    else { r = c; b = x; }
    
    return vec3<f32>(r + m, g + m, b + m);
}

// Palette function (cosine-based)
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// Hue shift
fn hueShift(col: vec3<f32>, shift: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735);
    return col * cos(shift) + cross(k, col) * sin(shift) + k * dot(k, col) * (1.0 - cos(shift));
}

// Tone mapping (ACES approximation)
fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
```

### UV Transformations

```wgsl
// 2D rotation matrix
fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Kaleidoscope mirror
fn kaleidoscope(uv: vec2<f32>, segments: f32) -> vec2<f32> {
    let angle = atan2(uv.y, uv.x);
    let radius = length(uv);
    let segmentAngle = 6.28318 / segments;
    let mirroredAngle = abs(fract(angle / segmentAngle + 0.5) - 0.5) * segmentAngle;
    return vec2<f32>(cos(mirroredAngle), sin(mirroredAngle)) * radius;
}

// Polar to cartesian
fn polarToCartesian(uv: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(uv.x * cos(uv.y), uv.x * sin(uv.y));
}

// Cartesian to polar
fn cartesianToPolar(uv: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(length(uv), atan2(uv.y, uv.x));
}
```

### SDF Primitives (for raymarching)

```wgsl
// Sphere
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

// Box
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, vec3<f32>(0.0)));
}

// Cylinder
fn sdCylinder(p: vec3<f32>, c: vec2<f32>) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - c;
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// Smooth union
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// Normal calculation
fn calcNormal(p: vec3<f32>, mapFn: fn(vec3<f32>) -> f32) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.001;
    return normalize(
        e.xyy * mapFn(p + e.xyy) +
        e.yyx * mapFn(p + e.yyx) +
        e.yxy * mapFn(p + e.yxy) +
        e.xxx * mapFn(p + e.xxx)
    );
}
```

---

## Multi-Pass Shader Pattern

### Pass 1: Data Generation

```wgsl
// File: my-shader-pass1.wgsl
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let uv = vec2<f32>(gid.xy) / u.config.zw;
    
    // Generate some data (e.g., vector field)
    let angle = fbm(uv * 5.0, 4) * 6.28318;
    let field = vec2<f32>(cos(angle), sin(angle));
    
    // Store in dataTextureA for Pass 2
    textureStore(dataTextureA, gid.xy, vec4<f32>(field, 0.0, 1.0));
    
    // Also write initial color
    let color = generateColor(uv);
    textureStore(writeTexture, gid.xy, color);
    
    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```

### Pass 2: Compositing

```wgsl
// File: my-shader-pass2.wgsl
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let uv = vec2<f32>(gid.xy) / u.config.zw;
    
    // Read from Pass 1 output
    let pass1Color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let vectorField = textureLoad(dataTextureA, gid.xy, 0).xy;
    
    // Use vector field to distort
    let displacedUV = uv + vectorField * 0.1;
    let displacedColor = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);
    
    // Composite
    let finalColor = mix(pass1Color, displacedColor, 0.5);
    
    textureStore(writeTexture, gid.xy, finalColor);
    
    // Pass depth through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
```

### JSON for Multi-Pass

```json
{
  "id": "my-shader-pass1",
  "name": "My Shader Pass 1",
  "url": "shaders/my-shader-pass1.wgsl",
  "category": "distortion",
  "features": ["multi-pass-1"],
  "multipass": {
    "pass": 1,
    "totalPasses": 2,
    "nextShader": "my-shader-pass2"
  }
}
```

---

## Audio Reactivity Patterns

### Basic Audio Input

```wgsl
// zoom_config.x contains audio FFT magnitude (0.0 - 1.0)
let audio = u.zoom_config.x;
```

### Bass Pulse

```wgsl
let pulse = 1.0 + audio * 0.5;
let scale = vec2<f32>(pulse);
uv = (uv - 0.5) / scale + 0.5;
```

### Audio Color Shift

```wgsl
let hueShift = audio * 0.5;
color = hueShift(color, hueShift);
```

### Beat Detection

```wgsl
// Simple beat detection
let isBeat = step(0.7, audio);
let flash = isBeat * 0.3;
color = color + vec3<f32>(flash);
```

---

## RGBA Semantic Encoding Guide

The alpha channel is wasted at `1.0`. Every shader should encode one of:

| Convention | Alpha formula | When to use |
|------------|---------------|-------------|
| Bloom mask | `pow(max(0, luma - 0.6), 2) * 3.0` | Generative / HDR shaders |
| Depth passthrough | read from `readDepthTexture` and store verbatim | Whenever depth is available |
| Effect strength | `effectMagnitude` (0–1) | Distortion / overlay shaders |
| Trail age | `prev_alpha * 0.97` (decay each frame) | Temporal / particle shaders |
| Material ID | `0.0`=organic `0.5`=metal `1.0`=emissive | Multi-material scenes |
| Fresnel | `pow(1.0 - cosTheta, 5.0)` | Glass / water / chrome |

### Pattern 4: Bloom-Weight Alpha (recommended default)

```wgsl
let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
// Only pixels brighter than 0.6 contribute to bloom
let bloomWeight = pow(max(0.0, luma - 0.6), 2.0) * 3.0;
textureStore(writeTexture, coord, vec4<f32>(color, bloomWeight));
```

### Pattern 5: Simulation State Encoding (full RGBA as data)

```wgsl
// Store 4 simulation channels — color is derived at display time
let density  = computeDensity(uv);   // R
let velocity = computeVelocity(uv);  // G  (or pack vx,vy in RG)
let age      = prevAge + dt;          // B
let energy   = computeEnergy(uv);    // A
textureStore(writeTexture, coord, vec4<f32>(density, velocity, age, energy));
```

---

## Advanced Algorithm Reference

### Voronoi F2-F1 (ridge/vein patterns)
```wgsl
fn voronoiRidge(p: vec2<f32>) -> f32 {
    var F1 = 9.0; var F2 = 9.0;
    let ip = floor(p);
    for (var i = -2; i <= 2; i++) { for (var j = -2; j <= 2; j++) {
        let n = ip + vec2<f32>(f32(i), f32(j));
        let d = length(p - n - fract(sin(vec2<f32>(dot(n,vec2<f32>(127.1,311.7)),dot(n,vec2<f32>(269.5,183.3))))*43758.5));
        if (d < F1) { F2 = F1; F1 = d; } else if (d < F2) { F2 = d; }
    }}
    return F2 - F1;  // ridge value — use for mountain ranges, skin texture, cracks
}
```

### Curl Noise (divergence-free vector field)
```wgsl
fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
    let eps = 0.001;
    let dx = fbm(p + vec2<f32>(eps, 0.0), 4) - fbm(p - vec2<f32>(eps, 0.0), 4);
    let dy = fbm(p + vec2<f32>(0.0, eps), 4) - fbm(p - vec2<f32>(0.0, eps), 4);
    return vec2<f32>(dy, -dx) / (2.0 * eps);  // perpendicular gradient = divergence-free
}
```

### Complex Number Operations (for Mandelbrot / Möbius)
```wgsl
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x);
}
fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let d = dot(b,b) + 1e-6;
    return vec2<f32>(dot(a,b), a.y*b.x - a.x*b.y) / d;
}
// Möbius transform f(z) = (az+b)/(cz+d)
fn mobius(z: vec2<f32>, a: vec2<f32>, b: vec2<f32>, c: vec2<f32>, d: vec2<f32>) -> vec2<f32> {
    return cdiv(cmul(a,z)+b, cmul(c,z)+d);
}
```

### OkLab Color Mixing (perceptually uniform)
```wgsl
fn linear_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let l=pow(0.4122214708*c.r+0.5363325363*c.g+0.0514459929*c.b,1./3.);
    let m=pow(0.2119034982*c.r+0.6806995451*c.g+0.1073969566*c.b,1./3.);
    let s=pow(0.0883024619*c.r+0.2817188376*c.g+0.6299787005*c.b,1./3.);
    return vec3<f32>(0.2104542553*l+0.7936177850*m-0.0040720468*s,
                     1.9779984951*l-2.4285922050*m+0.4505937099*s,
                     0.0259040371*l+0.7827717662*m-0.8086757660*s);
}
fn oklab_to_linear(c: vec3<f32>) -> vec3<f32> {
    let l=(c.x+0.3963377774*c.y+0.2158037573*c.z); let lc=l*l*l;
    let m=(c.x-0.1055613458*c.y-0.0638541728*c.z); let mc=m*m*m;
    let s=(c.x-0.0894841775*c.y-1.2914855480*c.z); let sc=s*s*s;
    return vec3<f32>(4.0767416621*lc-3.3077115913*mc+0.2309699292*sc,
                    -1.2684380046*lc+2.6097574011*mc-0.3413193965*sc,
                    -0.0041960863*lc-0.7034186147*mc+1.7076147010*sc);
}
fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    return oklab_to_linear(mix(linear_to_oklab(a), linear_to_oklab(b), t));
}
```

### Halton Quasi-Random Sequence (better than hash for sampling)
```wgsl
fn halton2(i: u32) -> f32 {  // base-2
    var f = 1.0; var r = 0.0; var n = i;
    loop { if (n == 0u) { break; } f *= 0.5; r += f * f32(n & 1u); n >>= 1u; }
    return r;
}
fn halton3(i: u32) -> f32 {  // base-3
    var f = 1.0; var r = 0.0; var n = i;
    loop { if (n == 0u) { break; } f /= 3.0; r += f * f32(n % 3u); n /= 3u; }
    return r;
}
// Use: vec2(halton2(sampleIdx), halton3(sampleIdx)) for 2D jitter
```

### Blackbody Color Temperature
```wgsl
fn blackbody(T: f32) -> vec3<f32> {
    let t = clamp(T, 1000.0, 40000.0) / 100.0;
    let r = select(clamp(329.698727*pow(t-60.0,-0.1332)/255.0,0.0,1.0), 1.0, t<=66.0);
    let g = select(clamp(288.1221695*pow(t-60.0,-0.0755)/255.0,0.0,1.0),
                   clamp((99.4708*log(t)-161.1196)/255.0,0.0,1.0), t<=66.0);
    let b = select(1.0, select(0.0, clamp((138.5177*log(t-10.0)-305.0448)/255.0,0.0,1.0), t>19.0), t>=66.0);
    return vec3<f32>(r,g,b);
}
```

---

## Quick Checklist for Shader Submission

- [ ] Header comment with name, category, features
- [ ] All 13 bindings declared in correct order
- [ ] Uniforms struct matches specification
- [ ] `@compute @workgroup_size(...)` present (16×16 recommended default; do NOT change sizes on shaders using `var<workgroup>` or `local_invocation_id`)
- [ ] Both `writeTexture` AND `writeDepthTexture` written
- [ ] Alpha is calculated (not hardcoded to 1.0)
- [ ] Parameters use safe patterns (no div by zero, etc.)
- [ ] Shader renders at all param values (0.0, 1.0, random)
- [ ] JSON definition created with correct category
- [ ] Unique ID (not conflicting with existing shaders)
