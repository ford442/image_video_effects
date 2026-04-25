# Shader Upgrade Swarm - Technical Reference

Quick reference for agents working on shader upgrades.

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
