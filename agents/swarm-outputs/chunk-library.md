# WGSL Shader Chunk Library
## Created by Agent 2A - Shader Surgeon / Chunk Librarian
## Date: 2026-03-22

---

## Overview

This library contains reusable WGSL code chunks extracted from the image_video_effects shader collection. These chunks are categorized by functionality and can be combined to create hybrid shaders.

---

## Table of Contents

1. [Noise Functions](#1-noise-functions)
2. [Color Utilities](#2-color-utilities)
3. [UV Transformations](#3-uv-transformations)
4. [SDF Primitives](#4-sdf-primitives)
5. [Lighting Effects](#5-lighting-effects)
6. [Compatibility Matrix](#6-compatibility-matrix)
7. [Usage Guidelines](#7-usage-guidelines)
8. [Chunk Sources Index](#8-chunk-sources-index)
9. [Agent 3C — Spectral Computation Pioneer Chunks](#9-agent-3c--spectral-computation-pioneer-chunks)
10. [Agent 2a — Phase A Shader Upgrade Additions](#10-agent-2a--phase-a-shader-upgrade-additions)
11. [Agent 3c — Phase C Additions](#11-agent-3c--phase-c-additions)

---

## 1. Noise Functions

### 1.1 Hash Functions

#### `hash12` - 2D to 1D Hash
**Source:** `gen_grid.wgsl`  
**Description:** Generates pseudo-random value from 2D coordinates

```wgsl
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
```

**Compatibility:** Works with any vec2<f32> input  
**Returns:** f32 in range [0, 1]

---

#### `hash22` - 2D to 2D Hash
**Source:** `gen_grid.wgsl`, `voronoi-glass.wgsl`  
**Description:** Generates 2D pseudo-random vector

```wgsl
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}
```

**Compatibility:** Input vec2<f32>, Output vec2<f32> in range [0, 1]  
**Use Cases:** Voronoi cell centers, random directions

---

### 1.2 Value Noise

#### `valueNoise` - 2D Value Noise
**Source:** `gen_grid.wgsl`  
**Description:** Smooth interpolated noise using quintic interpolation

```wgsl
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    
    // Quintic interpolation curve
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    
    // Four corners
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
```

**Compatibility:** Requires hash12  
**Returns:** Smooth f32 in range [0, 1]

---

### 1.3 FBM (Fractal Brownian Motion)

#### `fbm2` - 2D FBM
**Source:** `gen_grid.wgsl`, `stellar-plasma.wgsl`  
**Description:** Multi-octave noise for organic/cloud-like patterns

```wgsl
fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    
    return value;
}
```

**Compatibility:** Requires valueNoise or noise function  
**Parameters:**
- `p`: Position coordinates
- `octaves`: Number of noise layers (typically 4-8)

---

#### `fbm3` - 3D FBM
**Source:** `gen-xeno-botanical-synth-flora.wgsl`  
**Description:** 3D version for volumetric noise

```wgsl
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453123);
}

fn noise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (vec3<f32>(3.0) - 2.0 * f);
    return mix(
        mix(
            mix(dot(hash3(p + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                dot(hash3(p + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), f2.x),
            mix(dot(hash3(p + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                dot(hash3(p + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), f2.x), f2.y),
        mix(
            mix(dot(hash3(p + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                dot(hash3(p + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), f2.x),
            mix(dot(hash3(p + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                dot(hash3(p + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), f2.x), f2.y),
        f2.z);
}

fn fbm3(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        f += w * noise3(pos);
        pos *= 2.0;
        w *= 0.5;
    }
    return f;
}
```

**Use Cases:** Volumetric clouds, 3D textures, time-varying 2D noise

---

### 1.4 Domain Warping

#### `domainWarp` - Nested FBM Distortion
**Source:** `gen_grid.wgsl`, `stellar-plasma.wgsl`  
**Description:** Creates organic flowing distortions via nested FBM

```wgsl
fn domainWarp(uv: vec2<f32>, time: f32, scale: f32, amount: f32) -> vec2<f32> {
    // First level of distortion
    let q = vec2<f32>(
        fbm2(uv * scale + vec2<f32>(0.0, time * 0.1), 4),
        fbm2(uv * scale + vec2<f32>(5.2, 1.3 + time * 0.1), 4)
    );
    
    // Second level - nested distortion
    let r = vec2<f32>(
        fbm2(uv * scale + 4.0 * q + vec2<f32>(1.7 - time * 0.15, 9.2), 4),
        fbm2(uv * scale + 4.0 * q + vec2<f32>(8.3 - time * 0.15, 2.8), 4)
    );
    
    // Final displacement
    var warped = uv + amount * r;
    
    return warped;
}
```

**Compatibility:** Requires fbm2  
**Use Cases:** Liquid distortion, organic motion, cloud-like warping

---

## 2. Color Utilities

### 2.1 Color Space Conversions

#### `hsl2rgb` - HSL to RGB Conversion
**Source:** `liquid-metal.wgsl`  
**Description:** Converts HSL color values to RGB

```wgsl
fn hsl2rgb(h: f32, s: f32, l: f32) -> vec3<f32> {
    let c = (1.0 - abs(2.0 * l - 1.0)) * s;
    var x = c * (1.0 - abs((h * 6.0) % 2.0 - 1.0));
    let m = l - c / 2.0;

    var r = 0.0;
    var g = 0.0;
    var b = 0.0;

    if (h < 1.0/6.0) { r = c; g = x; b = 0.0; }
    else if (h < 2.0/6.0) { r = x; g = c; b = 0.0; }
    else if (h < 3.0/6.0) { r = 0.0; g = c; b = x; }
    else if (h < 4.0/6.0) { r = 0.0; g = x; b = c; }
    else if (h < 5.0/6.0) { r = x; g = 0.0; b = c; }
    else { r = c; g = 0.0; b = x; }

    return vec3<f32>(r+m, g+m, b+m);
}
```

**Parameters:**
- `h`: Hue [0, 1]
- `s`: Saturation [0, 1]
- `l`: Lightness [0, 1]

---

#### `rgb2hsv` - RGB to HSV Conversion
**Source:** `chromatic-manifold.wgsl`  
**Description:** Converts RGB to HSV color space

```wgsl
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    var p = mix(vec4<f32>(c.b, c.g, K.w, K.z), vec4<f32>(c.g, c.b, K.x, K.y), step(c.b, c.g));
    var q = mix(vec4<f32>(p.x, p.y, p.w, c.r), vec4<f32>(c.r, p.y, p.z, p.x), step(p.x, c.r));
    var d = q.x - min(q.w, q.y);
    let h = abs((q.w - q.y) / (6.0 * d + 1e-10) + K.x);
    return vec3<f32>(h, d, q.x);
}
```

---

### 2.2 Palettes

#### `palette` - Cosine-based Color Palette
**Source:** `gen-xeno-botanical-synth-flora.wgsl`  
**Description:** Inigo Quilez's cosine palette

```wgsl
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}
```

**Parameters:**
- `t`: Time/phase input
- `a`: Base color offset
- `b`: Color amplitude
- `c`: Color frequency
- `d`: Color phase

**Common Presets:**
- Sunset: `palette(t, vec3(0.5), vec3(0.5), vec3(1.0), vec3(0.0, 0.33, 0.67))`
- Ocean: `palette(t, vec3(0.5), vec3(0.5), vec3(1.0, 1.0, 0.5), vec3(0.8, 0.9, 0.3))`

---

### 2.3 Color Effects

#### `hueShift` - RGB Hue Rotation
**Source:** `stellar-plasma.wgsl`  
**Description:** Rotates hue of RGB color

```wgsl
fn hueShift(color: vec3<f32>, hue: f32) -> vec3<f32> {
    let k = vec3<f32>(0.57735, 0.57735, 0.57735);
    let cosAngle = cos(hue);
    return color * cosAngle + cross(k, color) * sin(hue) + k * dot(k, color) * (1.0 - cosAngle);
}
```

**Parameters:**
- `color`: Input RGB color
- `hue`: Rotation angle in radians

---

#### `fresnelSchlick` - Fresnel Effect
**Source:** `crystal-facets.wgsl`  
**Description:** Schlick's approximation for Fresnel reflectance

```wgsl
fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}
```

**Use Cases:** Metallic reflections, glass edges, water surfaces

---

## 3. UV Transformations

### 3.1 Basic Transforms

#### `rot2` - 2D Rotation Matrix
**Source:** `kaleidoscope.wgsl`, `gen-xeno-botanical-synth-flora.wgsl`  
**Description:** Returns rotation matrix for given angle

```wgsl
fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}
```

**Use:** `uv = rot2(angle) * uv;`

---

### 3.2 Geometric Transforms

#### `kaleidoscope` - Kaleidoscope Mirror
**Source:** `kaleidoscope.wgsl`  
**Description:** Mirrors UV space into N segments

```wgsl
fn kaleidoscope(uv: vec2<f32>, segments: f32) -> vec2<f32> {
    let angle = atan2(uv.y, uv.x);
    let radius = length(uv);
    let segmentAngle = 6.28318 / segments;
    let mirroredAngle = abs(fract(angle / segmentAngle + 0.5) - 0.5) * segmentAngle;
    return vec2<f32>(cos(mirroredAngle), sin(mirroredAngle)) * radius;
}
```

**Parameters:**
- `uv`: Centered coordinates (origin at center)
- `segments`: Number of mirror segments

---

#### `cartesianToPolar` / `polarToCartesian`
**Source:** Derived from kaleidoscope pattern  
**Description:** Coordinate system conversions

```wgsl
fn cartesianToPolar(uv: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(length(uv), atan2(uv.y, uv.x));
}

fn polarToCartesian(uv: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(uv.x * cos(uv.y), uv.x * sin(uv.y));
}
```

---

### 3.3 Complex Transforms

#### `mobiusTransform` - Mobius Transformation
**Source:** `hyperbolic-dreamweaver.wgsl`  
**Description:** Hyperbolic geometry transformation

```wgsl
fn mobiusTransform(p: vec2<f32>, center: vec2<f32>, scale: f32, angle: f32) -> vec2<f32> {
    var q = p - center;
    // Rotate
    let c = cos(angle);
    let s = sin(angle);
    q = vec2(q.x * c - q.y * s, q.x * s + q.y * c);
    // Hyperbolic scale
    let d = length(q);
    let hyperbolic_scale = scale / (1.0 + d * d * 0.5);
    return center + q * hyperbolic_scale;
}
```

---

## 4. SDF Primitives

### 4.1 Basic Primitives

#### `sdSphere` - Sphere SDF
**Source:** `gen-xeno-botanical-synth-flora.wgsl`  
**Description:** Signed distance to sphere

```wgsl
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}
```

---

#### `sdBox` - Box SDF
**Source:** Technical Reference  
**Description:** Signed distance to axis-aligned box

```wgsl
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, vec3<f32>(0.0)));
}
```

---

#### `sdCylinder` - Cylinder SDF
**Source:** `gen-xeno-botanical-synth-flora.wgsl`  
**Description:** Signed distance to infinite cylinder

```wgsl
fn sdCylinder(p: vec3<f32>, c: vec2<f32>) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - c;
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}
```

**Parameters:**
- `p`: Point in 3D space
- `c`: vec2(radius, height/2)

---

#### `sdCappedCone` - Capped Cone SDF
**Source:** `gen-xeno-botanical-synth-flora.wgsl`  
**Description:** Signed distance to capped cone

```wgsl
fn sdCappedCone(p: vec3<f32>, c: vec3<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz), p.y);
    let k1 = vec2<f32>(c.z, c.y);
    let k2 = vec2<f32>(c.z - c.x, 2.0 * c.y);
    let ca = vec2<f32>(q.x - min(q.x, (q.y < 0.0) ? c.x : c.z), abs(q.y) - c.y);
    let cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot(k2, k2), 0.0, 1.0);
    var s = -1.0;
    if (cb.x < 0.0 && ca.y < 0.0) { s = 1.0; }
    return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}
```

**Parameters:**
- `c`: vec3(bottom_radius, height/2, top_radius)

---

### 4.2 Operations

#### `sdSmoothUnion` - Smooth Union
**Source:** `gen-xeno-botanical-synth-flora.wgsl`  
**Description:** Smoothly blends two SDFs

```wgsl
fn sdSmoothUnion(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}
```

---

#### `calcNormal` - SDF Normal Calculation
**Source:** `gen-xeno-botanical-synth-flora.wgsl`  
**Description:** Calculates normal from SDF using tetrahedron technique

```wgsl
fn calcNormal(p: vec3<f32>, mapFn: fn(vec3<f32>) -> vec2<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.001;
    return normalize(
        e.xyy * mapFn(p + e.xyy).x +
        e.yyx * mapFn(p + e.yyx).x +
        e.yxy * mapFn(p + e.yxy).x +
        e.xxx * mapFn(p + e.xxx).x
    );
}
```

---

## 5. Lighting Effects

### 5.1 Glow and Bloom

#### `glow` - Distance-based Glow
**Source:** `anamorphic-flare.wgsl`  
**Description:** Creates soft glow from distance field

```wgsl
fn glow(dist: f32, radius: f32, intensity: f32) -> f32 {
    return exp(-dist * dist / (radius * radius)) * intensity;
}
```

---

#### `centralGlow` - Central Glow/Halo
**Source:** `anamorphic-flare.wgsl`  
**Description:** Core glow with corona

```wgsl
fn centralGlow(uv: vec2<f32>, center: vec2<f32>, size: f32) -> vec3<f32> {
    let dist = length(uv - center);
    
    // Core glow
    let core = exp(-dist * 15.0 / size);
    
    // Corona (wider, softer)
    let corona = exp(-dist * 5.0 / size) * 0.3;
    
    // Combined with slight blue tint
    let glowTint = vec3<f32>(0.8, 0.9, 1.0);
    
    return (core + corona) * glowTint;
}
```

---

### 5.2 Light Calculations

#### `specularHighlight` - Blinn-Phong Specular
**Source:** `liquid-metal.wgsl`  
**Description:** Calculates specular highlight

```wgsl
fn specularHighlight(
    viewDir: vec3<f32>, 
    lightDir: vec3<f32>, 
    normal: vec3<f32>, 
    power: f32
) -> f32 {
    let halfDir = normalize(lightDir + viewDir);
    return pow(max(dot(normal, halfDir), 0.0), power);
}
```

---

### 5.3 Volumetric Effects

#### `volumetricRays` - God Rays
**Source:** `anamorphic-flare.wgsl`  
**Description:** Light ray simulation

```wgsl
fn volumetricRays(uv: vec2<f32>, lightPos: vec2<f32>, intensity: f32) -> f32 {
    let toLight = lightPos - uv;
    let angle = atan2(toLight.y, toLight.x);
    let dist = length(toLight);
    
    // Ray pattern based on angle
    let rayPattern = pow(sin(angle * 12.0 + dist * 20.0), 4.0);
    let radialFalloff = 1.0 / (1.0 + dist * 3.0);
    
    return rayPattern * radialFalloff * intensity * 0.3;
}
```

---

## 6. Compatibility Matrix

| Chunk | Dependencies | Safe Params | Notes |
|-------|-------------|-------------|-------|
| hash12 | None | Any vec2 | Fast, good distribution |
| hash22 | None | Any vec2 | Returns vec2 for directions |
| valueNoise | hash12 | Any vec2 | Smooth, 2D only |
| fbm2 | valueNoise | octaves: 1-8 | Higher octaves = slower |
| fbm3 | noise3 | Any vec3 | For volumetric effects |
| domainWarp | fbm2 | amount: 0-1 | Can distort heavily |
| hsl2rgb | None | h,s,l: 0-1 | Full range safe |
| hueShift | None | angle: any rad | Periodic |
| palette | None | t: any | Periodic in t |
| rot2 | None | angle: any rad | Periodic |
| kaleidoscope | None | segments: >0 | segments < 3 = artifacts |
| mobiusTransform | None | scale > 0 | Hyperbolic effect |
| sdSphere | None | radius >= 0 | Basic primitive |
| sdBox | None | size >= 0 | Axis-aligned |
| sdCylinder | None | r,h >= 0 | Y-up cylinder |
| sdSmoothUnion | None | k > 0 | k=0 = hard union |
| fresnelSchlick | None | F0: 0-1 | Typical F0: 0.02-0.95 |
| glow | None | radius > 0 | Division by radius |
| bass_env | None | bass/mids: 0-1 | Audio envelope multiplier |
| hsv2rgb | None | h,s,v: 0-1 | Standard HSV conversion |
| paletteSmoothstep | None | t: 0-1 | 4-color smoothstep gradient |
| heatMapGradient | None | t: 0-1 | Black→blue→yellow→red→white |
| iridescence | None | theta: any | Thin-film cosine color |
| nearestHexCenter | None | scale > 0 | Returns center in scaled space |
| voronoi2D | hash22 | st: any | Returns struct with dist/point/cell |
| sdSegment | None | 2D segment | Epsilon-guarded denominator |
| rdPulse | glow | speed, width > 0 | Radial pulse + envelope |
| hash11 | None | p: any f32 | Fast 1D sine hash |
| hash3_packed | None | p: any vec2 | Returns 3 uncorrelated hashes |
| rgbToLuma | None | rgb: any vec3 | Rec. 709 luma weights |
| sigmoidContrast | None | k > 0 | S-curve contrast boost |
| bayer4x4 | None | pixel coords | 4x4 ordered dither threshold |
| halftoneDot | None | freq > 0 | Circular halftone dot mask |
| applyVignette | None | strength: 0-1 | Soft darkening toward corners |
| edgeVignette | None | strength: 0-1 | Harder photocopy edge darkening |
| scanlineBloom | None | luma >= 0 | Scanline brightness modulation |
| halationGlow | texture + sampler | radius > 0 | 4-tap neighbor luma glow |
| phosphorMask | fbm | strength: 0-1 | FBM-tinted CRT RGB mask |
| scanlineJitter | hash21 | intensity: 0-1 | Per-row horizontal jitter |
| interferenceFringes | None | freq > 0 | Thin-film fringe pattern |
| lensDistort | None | center in UV | Barrel/pincushion distortion |
| displacedUV | fbm | strength: 0-1 | FBM-driven UV displacement |
| heatShimmer | fbm | strength: 0-1 | Heat-haze UV warp |
| sdSpiral | None | arms > 0 | Angular distance to spiral arms |
| sdCircle | None | r >= 0 | 2D signed circle distance |
| hexDistance | None | scale > 0 | Hexagonal grid cell distance |
| causticPattern | None | p: any vec2 | Summed sinusoid caustics |
| turing_pattern | fbm | scale > 0 | FBM-based activator/inhibitor |
| multi_scale_turing | turing_pattern | params: vec4 | 3-layer Turing composition |
| iridescentSubstrate | fbm | strength: 0-1 | FBM-driven opal iridescence |
| pulseBloom | None | radius > 0 | Expanding radial ring glow |

---

## 7. Usage Guidelines

### 7.1 Parameter Safety

Always use safe parameter patterns:

```wgsl
// GOOD: Normalized intensity with minimum
let intensity = mix(0.1, 2.0, u.zoom_params.x);

// GOOD: Frequency with minimum to avoid division by zero
let frequency = mix(0.5, 10.0, u.zoom_params.y);

// BAD: Can divide by zero
let scale = 1.0 / u.zoom_params.x;

// FIXED:
let scale = 1.0 / (u.zoom_params.x + 0.001);
```

### 7.2 Chunk Combination Rules

1. **Namespace Management**: Prefix chunk functions with chunk name to avoid collisions
2. **UV Space Consistency**: Ensure all chunks use same UV space (0-1 or -1 to 1)
3. **Alpha Accumulation**: When combining effects, use proper alpha blending:
   ```wgsl
   let alpha = baseAlpha * (1.0 - effectStrength) + effectAlpha * effectStrength;
   ```

### 7.3 Performance Considerations

- FBM octaves: 4-6 for real-time, 8+ for offline
- SDF raymarching: Keep step count < 100 for 60fps
- Multiple texture samples: Cache results when possible

---

## 8. Chunk Sources Index

| Shader File | Chunks Extracted |
|-------------|-----------------|
| `gen_grid.wgsl` | hash12, hash22, hash33, valueNoise, fbm2, domainWarp |
| `stellar-plasma.wgsl` | hash, noise (value), fbm, hueShift |
| `gen-xeno-botanical-synth-flora.wgsl` | hash3, noise3, fbm3, palette, sdCappedCone, sdCylinder, sdSphere, calcNormal |
| `kaleidoscope.wgsl` | kaleidoscope logic |
| `hyperbolic-dreamweaver.wgsl` | mobiusTransform, chromatic aberration |
| `liquid-metal.wgsl` | hsl2rgb, schlickFresnel, specular calculation |
| `chromatic-manifold.wgsl` | rgb2hsv, wavelength-based alpha |
| `anamorphic-flare.wgsl` | glow, centralGlow, volumetricRays, hexagonAperture |
| `crystal-facets.wgsl` | fresnelSchlick, path length calculation |
| `hex-circuit.wgsl` | hex grid calculation, edge detection |
| `voronoi-glass.wgsl` | voronoi pattern, hash22 usage |

---

*End of Chunk Library - 42 Functions Documented*

## 9. Agent 3C — Spectral Computation Pioneer Chunks

### 9.1 Tone Mapping

#### `toneMapACES` — ACES Filmic Tone Mapper
**Source:** `spec-blackbody-thermal.wgsl`, `spec-temporal-path-tracer.wgsl`

```wgsl
fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}
```

#### `toneMapFilmic` — Hejl-Richardson Filmic Tone Mapper
**Source:** Agent 3C specification

```wgsl
fn toneMapFilmic(x: vec3<f32>) -> vec3<f32> {
    let a = max(vec3(0.0), x - 0.004);
    return (a * (6.2 * a + 0.5)) / (a * (6.2 * a + 1.7) + 0.06);
}
```

---

### 9.2 Bicubic Sampling

#### `catmullRom` — Catmull-Rom Weights
**Source:** `spec-bicubic-crystal.wgsl`

```wgsl
fn catmullRom(t: f32) -> vec4<f32> {
    let t2 = t * t;
    let t3 = t2 * t;
    return vec4<f32>(
        -0.5*t3 + t2 - 0.5*t,
        1.5*t3 - 2.5*t2 + 1.0,
        -1.5*t3 + 2.0*t2 + 0.5*t,
        0.5*t3 - 0.5*t2
    );
}
```

#### `sampleBicubic` — Bicubic Catmull-Rom Texture Sampling
**Source:** `spec-bicubic-crystal.wgsl`

```wgsl
fn sampleBicubic(tex: texture_2d<f32>, samp: sampler, uv: vec2<f32>, texSize: vec2<f32>) -> vec4<f32> {
    let pixel = uv * texSize - 0.5;
    let f = fract(pixel);
    let base = floor(pixel);

    let wx = catmullRom(f.x);
    let wy = catmullRom(f.y);

    var result = vec4<f32>(0.0);
    for (var j = -1; j <= 2; j = j + 1) {
        for (var i = -1; i <= 2; i = i + 1) {
            let coord = (base + vec2<f32>(f32(i), f32(j)) + 0.5) / texSize;
            let s = textureSampleLevel(tex, samp, coord, 0.0);
            let weight = wx[i + 1] * wy[j + 1];
            result += s * weight;
        }
    }
    return result;
}
```

---

### 9.3 Analytic Derivative Noise

#### `noiseWithDerivative` — Perlin Noise with Analytic Gradient
**Source:** `spec-analytic-noise-flow.wgsl`

```wgsl
fn noiseWithDerivative(p: vec2<f32>) -> vec3<f32> {
    let i = floor(p);
    let f = fract(p);

    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let du = 30.0 * f * f * (f * (f - 2.0) + 1.0);

    let a = hash2(i + vec2<f32>(0.0, 0.0));
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));

    let k0 = a;
    let k1 = b - a;
    let k2 = c - a;
    let k4 = a - b - c + d;

    let value = k0 + k1 * u.x + k2 * u.y + k4 * u.x * u.y;
    let derivative = vec2<f32>(
        (k1 + k4 * u.y) * du.x,
        (k2 + k4 * u.x) * du.y
    );

    return vec3<f32>(value, derivative);
}
```

---

### 9.4 Quaternion Math

#### `quaternionMul` — Quaternion Multiplication
**Source:** `spec-quaternion-julia.wgsl`

```wgsl
fn quaternionMul(a: vec4<f32>, b: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(
        a.x*b.x - a.y*b.y - a.z*b.z - a.w*b.w,
        a.x*b.y + a.y*b.x + a.z*b.w - a.w*b.z,
        a.x*b.z - a.y*b.w + a.z*b.x + a.w*b.y,
        a.x*b.w + a.y*b.z - a.z*b.y + a.w*b.x
    );
}
```

#### `quaternionJuliaDE` — Quaternion Julia Distance Estimator
**Source:** `spec-quaternion-julia.wgsl`

```wgsl
fn quaternionJuliaDE(p: vec3<f32>, c: vec4<f32>) -> f32 {
    var q = vec4<f32>(p, 0.0);
    var dq = vec4<f32>(1.0, 0.0, 0.0, 0.0);

    for (var i: i32 = 0; i < 12; i = i + 1) {
        dq = 2.0 * quaternionMul(q, dq);
        q = quaternionMul(q, q) + c;
        if (dot(q, q) > 256.0) { break; }
    }

    let r = length(q);
    let dr = length(dq);
    return 0.5 * r * log(r) / max(dr, 0.001);
}
```

---

### 9.5 Spectral Rendering

#### `cauchyIOR` — Cauchy's Equation for Refractive Index
**Source:** `spec-prismatic-dispersion.wgsl`

```wgsl
fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
    let lambdaUm = wavelengthNm * 0.001;
    return A + B / (lambdaUm * lambdaUm);
}
```

#### `wavelengthToRGB` — Simplified CIE Color Matching
**Source:** `spec-prismatic-dispersion.wgsl`, `spec-iridescence-engine.wgsl`

```wgsl
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
    let g = 1.0 - abs(t - 0.4) * 3.0;
    let b = 1.0 - smoothstep(0.0, 0.4, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}
```

---

### 9.6 Runge-Kutta Advection

#### `advectRK4` — 4th-Order Runge-Kutta Position Advection
**Source:** `spec-runge-kutta-advection.wgsl`

```wgsl
fn advectRK4(pos: vec2<f32>, dt: f32, time: f32,
             sampleVelocity: fn(vec2<f32>, f32) -> vec2<f32>) -> vec2<f32> {
    let k1 = sampleVelocity(pos, time);
    let k2 = sampleVelocity(pos + k1 * dt * 0.5, time);
    let k3 = sampleVelocity(pos + k2 * dt * 0.5, time);
    let k4 = sampleVelocity(pos + k3 * dt, time);
    return pos + (k1 + 2.0*k2 + 2.0*k3 + k4) * dt / 6.0;
}
```

---

## 10. Agent 2a — Phase A Shader Upgrade Additions

### 10.1 Reactive Helpers

#### `bass_env` — Audio Bass Envelope
**Source:** `luma-echo-warp.wgsl`, `chronos-brush.wgsl`  
**Description:** Multiplicative audio-reactivity envelope from bass and mids channels

```wgsl
fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}
```

**Compatibility:** No dependencies  
**Use Cases:** Scale effect strength, brush size, or glow intensity by audio

---

### 10.2 Color Utilities

#### `hsv2rgb` — HSV to RGB Conversion
**Source:** `chronos-brush.wgsl`  
**Description:** Compact HSV to RGB conversion using the IQ / GLSL method

```wgsl
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(vec3<f32>(h) + k) * 6.0 - vec3<f32>(3.0));
    return v * mix(vec3<f32>(1.0), clamp(p - vec3<f32>(1.0), vec3<f32>(0.0), vec3<f32>(1.0)), s);
}
```

**Parameters:**
- `h`: Hue [0, 1]
- `s`: Saturation [0, 1]
- `v`: Value [0, 1]

---

#### `paletteSmoothstep` — Smoothstep Gradient Palette
**Source:** `rd-on-video-pass2.wgsl`  
**Description:** Four-color palette blended via smoothstep thresholds

```wgsl
fn paletteSmoothstep(t: f32, c1: vec3<f32>, c2: vec3<f32>, c3: vec3<f32>, c4: vec3<f32>) -> vec3<f32> {
    let a = smoothstep(0.0, 0.35, t);
    let b = smoothstep(0.35, 0.75, t);
    let c = smoothstep(0.75, 1.0, t);
    return mix(mix(c1, c2, a), mix(c3, c4, c), b);
}
```

**Parameters:**
- `t`: Phase input [0, 1]
- `c1..c4`: Control colors at 0.0, ~0.35-0.75, ~0.75-1.0, 1.0

---

#### `heatMapGradient` — Heat Map Color Gradient
**Source:** `motion-heatmap.wgsl`  
**Description:** Classic thermal visualization gradient

```wgsl
fn heatMapGradient(t: f32) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    if (t < 0.3) {
        col = mix(vec3<f32>(0.0, 0.0, 0.2), vec3<f32>(0.0, 0.0, 1.0), t / 0.3);
    } else if (t < 0.6) {
        col = mix(vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(1.0, 1.0, 0.0), (t - 0.3) / 0.3);
    } else {
        col = mix(vec3<f32>(1.0, 1.0, 0.0), vec3<f32>(1.0, 0.0, 0.0), (t - 0.6) / 0.4);
    }
    if (t > 0.9) {
        col = mix(col, vec3<f32>(1.0, 1.0, 1.0), (t - 0.9) / 0.1);
    }
    return col;
}
```

**Compatibility:** No dependencies  
**Returns:** RGB heat color for `t` in [0, 1]

---

#### `iridescence` — Thin-Film Iridescent Color
**Source:** `gen-holographic-fracture.wgsl`  
**Description:** Cosine-based iridescence for holographic / thin-film effects

```wgsl
fn iridescence(theta: f32, shift: f32) -> vec3<f32> {
    let t = theta * 4.0 + shift;
    return 0.5 + 0.5 * cos(vec3<f32>(t, t + 2.094, t + 4.189));
}
```

**Parameters:**
- `theta`: Angle or phase input
- `shift`: Time/distance offset

---

### 10.3 UV Transformations / Geometric Patterns

#### `nearestHexCenter` — Hexagonal Grid Nearest Center
**Source:** `hex-mosaic.wgsl`, `quantum-prism.wgsl`  
**Description:** Finds the nearest hexagon cell center for a given UV

```wgsl
fn nearestHexCenter(uv: vec2<f32>, scale: f32) -> vec2<f32> {
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;
    let uvScaled = uv * scale;
    let uvA = uvScaled / r;
    let idA = floor(uvA + 0.5);
    let uvB = (uvScaled - h) / r;
    let idB = floor(uvB + 0.5);
    let centerA = idA * r;
    let centerB = idB * r + h;
    let distA = distance(uvScaled, centerA);
    let distB = distance(uvScaled, centerB);
    return select(centerB, centerA, distA < distB);
}
```

**Compatibility:** No dependencies  
**Returns:** Center coordinate in the same scaled space as `uv * scale`

---

#### `voronoi2D` — 2D Voronoi Pattern
**Source:** `interactive-voronoi-lens.wgsl`  
**Description:** Animated 2D Voronoi with time/chaos-driven jitter

```wgsl
struct VoronoiResult {
    dist: f32,
    point: vec2<f32>,
    cell: vec2<f32>,
};

fn voronoi2D(st: vec2<f32>, time: f32, chaos: f32) -> VoronoiResult {
    let i_st = floor(st);
    let f_st = fract(st);
    var result = VoronoiResult(1.0, vec2<f32>(0.0), vec2<f32>(0.0));
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            var point = hash22(i_st + neighbor);
            point = 0.5 + 0.5 * sin(time * chaos + 6.2831 * point);
            let d = length(neighbor + point - f_st);
            if (d < result.dist) {
                result.dist = d;
                result.point = point;
                result.cell = i_st + neighbor;
            }
        }
    }
    return result;
}
```

**Compatibility:** Requires `hash22`  
**Use Cases:** Voronoi lenses, cell patterns, mosaic effects

---

### 10.4 SDF Primitives

#### `sdSegment` — Signed Distance to Line Segment
**Source:** `gen-holographic-fracture.wgsl`  
**Description:** Signed distance from point `p` to segment `a-b`

```wgsl
fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / (dot(ba, ba) + 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}
```

**Compatibility:** No dependencies  
**Returns:** Euclidean distance to segment

---

### 10.5 Reactive Patterns

#### `rdPulse` — Reaction-Diffusion-like Radial Pulse
**Source:** `gen-bioelectric-pulse.wgsl`  
**Description:** Decaying radial wave pulse for organic pulse effects

```wgsl
fn rdPulse(p: vec2<f32>, center: vec2<f32>, time: f32, speed: f32, width: f32) -> f32 {
    let d = length(p - center);
    let phase = d * 8.0 - time * speed * 4.0;
    let wave = sin(phase) * 0.5 + 0.5;
    let envelope = exp(-d * d * 2.0) * (1.0 - smoothstep(0.0, 1.5, d));
    return wave * envelope * glow(d, width, 1.0);
}
```

**Compatibility:** Requires `glow`  
**Parameters:**
- `speed`: Wave propagation speed
- `width`: Glow/decay width

---

## Updated Chunk Sources Index

| Shader File | Chunks Extracted |
|-------------|-----------------|
| `gen_grid.wgsl` | hash12, hash22, hash33, valueNoise, fbm2, domainWarp |
| `stellar-plasma.wgsl` | hash, noise (value), fbm, hueShift |
| `gen-xeno-botanical-synth-flora.wgsl` | hash3, noise3, fbm3, palette, sdCappedCone, sdCylinder, sdSphere, calcNormal |
| `kaleidoscope.wgsl` | kaleidoscope logic |
| `hyperbolic-dreamweaver.wgsl` | mobiusTransform, chromatic aberration |
| `liquid-metal.wgsl` | hsl2rgb, schlickFresnel, specular calculation |
| `chromatic-manifold.wgsl` | rgb2hsv, wavelength-based alpha |
| `anamorphic-flare.wgsl` | glow, centralGlow, volumetricRays, hexagonAperture |
| `crystal-facets.wgsl` | fresnelSchlick, path length calculation |
| `hex-circuit.wgsl` | hex grid calculation, edge detection |
| `voronoi-glass.wgsl` | voronoi pattern, hash22 usage |
| `spec-blackbody-thermal.wgsl` | toneMapACES |
| `spec-temporal-path-tracer.wgsl` | toneMapACES |
| `spec-bicubic-crystal.wgsl` | catmullRom, sampleBicubic |
| `spec-analytic-noise-flow.wgsl` | noiseWithDerivative |
| `spec-quaternion-julia.wgsl` | quaternionMul, quaternionJuliaDE |
| `spec-prismatic-dispersion.wgsl` | cauchyIOR, wavelengthToRGB |
| `spec-iridescence-engine.wgsl` | wavelengthToRGB |
| `spec-runge-kutta-advection.wgsl` | advectRK4 |
| `interactive-voronoi-lens.wgsl` | voronoi2D |
| `hex-mosaic.wgsl` | nearestHexCenter |
| `quantum-prism.wgsl` | nearestHexCenter |
| `motion-heatmap.wgsl` | heatMapGradient |
| `chronos-brush.wgsl` | hsv2rgb, bass_env |
| `luma-echo-warp.wgsl` | bass_env |
| `rd-on-video-pass2.wgsl` | paletteSmoothstep |
| `gen-holographic-fracture.wgsl` | sdSegment, iridescence |
| `gen-bioelectric-pulse.wgsl` | rdPulse |
| `temporal-feedback-zoom-tracer.wgsl` | rgbToLuma |
| `temporal-rgb-ghost.wgsl` | applyVignette, displacedUV |
| `temporal-phosphor-burn.wgsl` | scanlineBloom, halationGlow, phosphorMask |
| `prism-displacement.wgsl` | hash11, lensDistort |
| `xerox-degrade.wgsl` | hash3_packed, bayer4x4, sigmoidContrast, halftoneDot, edgeVignette |
| `holographic-flicker.wgsl` | interferenceFringes, scanlineJitter |
| `chroma-vortex.wgsl` | sdSpiral |
| `gen-luminous-cauldron.wgsl` | causticPattern, heatShimmer |
| `generative-turing-veins.wgsl` | turing_pattern, multi_scale_turing |
| `gen-opal-circuit.wgsl` | hexDistance, iridescentSubstrate |
| `gen-bioreactor-bloom.wgsl` | sdCircle, pulseBloom |

---

## 11. Agent 3c — Phase C Additions

### 11.1 Hash & Noise Helpers

#### `hash11` — 1D Sine Hash
**Source:** `prism-displacement.wgsl`

```wgsl
fn hash11(p: f32) -> f32 {
    return fract(sin(p * 12.9898) * 43758.5453);
}
```

**Compatibility:** No dependencies  
**Returns:** f32 in range [0, 1]

---

#### `hash3_packed` — Packed 2D-to-3D Hash
**Source:** `xerox-degrade.wgsl`

```wgsl
fn hash3_packed(p: vec2<f32>) -> vec3<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}
```

**Compatibility:** No dependencies  
**Returns:** Three uncorrelated values in [0, 1]

---

### 11.2 Color & Tone Helpers

#### `rgbToLuma` — Rec. 709 Luminance
**Source:** `temporal-feedback-zoom-tracer.wgsl`, `temporal-rgb-ghost.wgsl`, `temporal-phosphor-burn.wgsl`

```wgsl
fn rgbToLuma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}
```

**Compatibility:** No dependencies

---

#### `sigmoidContrast` — S-Curve Contrast
**Source:** `xerox-degrade.wgsl`

```wgsl
fn sigmoidContrast(x: f32, k: f32) -> f32 {
    return 1.0 / (1.0 + exp(-k * (x - 0.5)));
}
```

**Compatibility:** No dependencies  
**Parameters:**
- `x`: input value
- `k`: contrast steepness (higher = harder contrast)

---

### 11.3 Dithering & Halftone

#### `bayer4x4` — Ordered Dither Matrix
**Source:** `xerox-degrade.wgsl`

```wgsl
fn bayer4x4(p: vec2<i32>) -> f32 {
    let x = u32(p.x) & 3u;
    let y = u32(p.y) & 3u;
    let M = array<u32, 16>(
        0u,  8u,  2u, 10u,
       12u,  4u, 14u,  6u,
        3u, 11u,  1u,  9u,
       15u,  7u, 13u,  5u
    );
    return f32(M[y * 4u + x]) * 0.0625;
}
```

**Compatibility:** No dependencies  
**Returns:** Threshold value in [0, 1]

---

#### `halftoneDot` — Circular Halftone Dot Mask
**Source:** `xerox-degrade.wgsl`

```wgsl
fn halftoneDot(luma: f32, uv: vec2<f32>, freq: f32) -> f32 {
    let grid = fract(uv * freq) - 0.5;
    let radius = luma * 0.707;
    return 1.0 - smoothstep(radius - 0.02, radius, length(grid));
}
```

**Compatibility:** No dependencies

---

### 11.4 Vignette

#### `applyVignette` — Soft Corner Darkening
**Source:** `temporal-rgb-ghost.wgsl`

```wgsl
fn applyVignette(color: vec3<f32>, uv: vec2<f32>, strength: f32) -> vec3<f32> {
    let d = length(uv - vec2<f32>(0.5));
    let v = smoothstep(0.5, 0.5 - strength, d);
    return color * v;
}
```

**Compatibility:** No dependencies

---

#### `edgeVignette` — Photocopy Edge Darkening
**Source:** `xerox-degrade.wgsl`

```wgsl
fn edgeVignette(uv: vec2<f32>, strength: f32) -> f32 {
    let d = length(uv - vec2<f32>(0.5));
    let v = smoothstep(0.7, 0.35, d);
    return mix(1.0, v, strength);
}
```

**Compatibility:** No dependencies  
**Returns:** Multiplier in [0, 1]

---

### 11.5 Temporal / CRT Effects

#### `scanlineBloom` — Scanline Brightness Modulation
**Source:** `temporal-phosphor-burn.wgsl`

```wgsl
fn scanlineBloom(uv: vec2<f32>, luma: f32, strength: f32) -> f32 {
    let scan = sin(uv.y * u.config.z * PI);
    let lineGlow = pow(abs(scan), 0.5);
    return 1.0 + luma * strength * lineGlow;
}
```

**Compatibility:** Requires global `PI` and `u.config.z` (resolution width)

---

#### `halationGlow` — Neighbor Luma Glow
**Source:** `temporal-phosphor-burn.wgsl`

```wgsl
fn halationGlow(uv: vec2<f32>, tex: texture_2d<f32>, samp: sampler, radius: f32) -> f32 {
    let off = radius / vec2<f32>(u.config.z, u.config.w);
    var glow = 0.0;
    glow = glow + rgbToLuma(textureSampleLevel(tex, samp, uv + vec2<f32>(off.x, 0.0), 0.0).rgb);
    glow = glow + rgbToLuma(textureSampleLevel(tex, samp, uv - vec2<f32>(off.x, 0.0), 0.0).rgb);
    glow = glow + rgbToLuma(textureSampleLevel(tex, samp, uv + vec2<f32>(0.0, off.y), 0.0).rgb);
    glow = glow + rgbToLuma(textureSampleLevel(tex, samp, uv - vec2<f32>(0.0, off.y), 0.0).rgb);
    return glow * 0.25;
}
```

**Compatibility:** Requires `rgbToLuma` and global `u.config.zw`

---

#### `phosphorMask` — FBM-Tinted CRT RGB Mask
**Source:** `temporal-phosphor-burn.wgsl`

```wgsl
fn phosphorMask(uv: vec2<f32>, time: f32, strength: f32) -> vec3<f32> {
    let n = fbm(uv * 120.0 + time * 0.05, 2);
    let r = 0.7 + 0.3 * sin(n * 6.28);
    let g = 0.7 + 0.3 * sin(n * 6.28 + 2.09);
    let b = 0.7 + 0.3 * sin(n * 6.28 + 4.18);
    return mix(vec3<f32>(1.0), vec3<f32>(r, g, b), strength);
}
```

**Compatibility:** Requires `fbm`

---

#### `scanlineJitter` — Per-Row Horizontal Jitter
**Source:** `holographic-flicker.wgsl`

```wgsl
fn scanlineJitter(uv: vec2<f32>, resolution: vec2<f32>, time: f32, intensity: f32) -> vec2<f32> {
    let line = floor(uv.y * resolution.y);
    let jitter = (hash21(vec2<f32>(line, time * 60.0)) - 0.5) * intensity * 0.04;
    return uv + vec2<f32>(jitter, 0.0);
}
```

**Compatibility:** Requires `hash21`

---

#### `interferenceFringes` — Thin-Film Fringe Pattern
**Source:** `holographic-flicker.wgsl`

```wgsl
fn interferenceFringes(uv: vec2<f32>, time: f32, freq: f32, strength: f32) -> f32 {
    let phase = uv.y * freq + uv.x * freq * 0.5 - time * 6.0;
    return pow(0.5 + 0.5 * cos(phase), 6.0) * strength;
}
```

**Compatibility:** No dependencies

---

### 11.6 UV Distortion

#### `lensDistort` — Barrel / Pincushion Distortion
**Source:** `prism-displacement.wgsl`

```wgsl
fn lensDistort(uv: vec2<f32>, center: vec2<f32>, k1: f32, k2: f32) -> vec2<f32> {
    let d = uv - center;
    let r2 = dot(d, d);
    let factor = 1.0 + k1 * r2 + k2 * r2 * r2;
    return center + d * factor;
}
```

**Compatibility:** No dependencies

---

#### `displacedUV` — FBM-Driven UV Displacement
**Source:** `temporal-rgb-ghost.wgsl`

```wgsl
fn displacedUV(uv: vec2<f32>, time: f32, strength: f32, seed: f32) -> vec2<f32> {
    let n1 = fbm(uv * 10.0 + vec2<f32>(seed, time * 0.2), 3);
    let n2 = fbm(uv * 10.0 + vec2<f32>(time * 0.15, seed + 31.0), 3);
    return uv + (vec2<f32>(n1, n2) - 0.5) * strength;
}
```

**Compatibility:** Requires `fbm`

---

#### `heatShimmer` — Heat-Haze UV Warp
**Source:** `gen-luminous-cauldron.wgsl`

```wgsl
fn heatShimmer(uv: vec2<f32>, time: f32, strength: f32) -> vec2<f32> {
    let warp = vec2<f32>(
        fbm(uv * 4.0 + vec2<f32>(time * 0.7, 0.0), 3),
        fbm(uv * 4.0 + vec2<f32>(0.0, time * 0.6), 3)
    );
    return uv + (warp - 0.5) * strength;
}
```

**Compatibility:** Requires `fbm`

---

### 11.7 SDF Primitives

#### `sdSpiral` — Spiral Arm Angular Distance
**Source:** `chroma-vortex.wgsl`

```wgsl
fn sdSpiral(p: vec2<f32>, arms: f32, tightness: f32) -> f32 {
    let r = length(p);
    let a = atan2(p.y, p.x);
    let spiralTarget = arms * r * tightness;
    let seg = abs(fract((a + spiralTarget) / TAU) - 0.5) * TAU;
    return seg;
}
```

**Compatibility:** Requires global `TAU`

---

#### `sdCircle` — 2D Signed Circle Distance
**Source:** `gen-bioreactor-bloom.wgsl`

```wgsl
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
    return length(p) - r;
}
```

**Compatibility:** No dependencies

---

#### `hexDistance` — Hexagonal Grid Cell Distance
**Source:** `gen-opal-circuit.wgsl`

```wgsl
fn hexDistance(uv: vec2<f32>, scale: f32) -> f32 {
    let q = sqrt(3.0);
    let h = uv * scale;
    let ax = vec2<f32>(q * 0.5, 0.5);
    let ay = vec2<f32>(0.0, 1.0);
    let cx = dot(h, ax);
    let cy = dot(h, ay - ax * 0.5);
    let rx = round(cx);
    let ry = round(cy);
    let rz = round(-cx - cy);
    let dx = abs(cx - rx);
    let dy = abs(cy - ry);
    let dz = abs(-cx - cy - rz);
    return max(max(dx, dy), dz);
}
```

**Compatibility:** No dependencies  
**Returns:** Distance to nearest hex cell center in axial coordinates

---

### 11.8 Generative Patterns

#### `causticPattern` — Summed Sinusoid Caustics
**Source:** `gen-luminous-cauldron.wgsl`

```wgsl
fn causticPattern(p: vec2<f32>, time: f32) -> f32 {
    var c = 0.0;
    c += 0.5 + 0.5 * sin(p.x * 12.0 + time * 2.3);
    c += 0.5 + 0.5 * sin(p.y * 14.0 - time * 1.7);
    c += 0.5 + 0.5 * sin((p.x + p.y) * 9.0 + time * 2.9);
    c += 0.5 + 0.5 * sin(length(p) * 16.0 - time * 3.1);
    return c * 0.25;
}
```

**Compatibility:** No dependencies

---

#### `turing_pattern` — FBM-Based Activator/Inhibitor
**Source:** `generative-turing-veins.wgsl`

```wgsl
fn turing_pattern(uv: vec2<f32>, time: f32, scale: f32, feed: f32) -> vec2<f32> {
    var p = uv * scale;
    let activator = fbm(p + vec2(time * 0.1, 0.0), 6);
    let inhibitor = fbm(p * 0.5 + vec2(0.0, time * 0.05), 4);
    let reaction = activator * inhibitor * (feed + 0.5);
    let diffusion_a = (fbm(p * 1.2, 5) - 0.5) * 0.1;
    let diffusion_i = (fbm(p * 0.6, 4) - 0.5) * 0.2;
    return vec2(activator + diffusion_a + reaction * 0.1, inhibitor + diffusion_i - reaction * 0.05);
}
```

**Compatibility:** Requires `fbm`

---

#### `multi_scale_turing` — Three-Layer Turing Composition
**Source:** `generative-turing-veins.wgsl`

```wgsl
fn multi_scale_turing(uv: vec2<f32>, time: f32, params: vec4<f32>, bass: f32) -> vec4<f32> {
    let s1 = params.x * 2.0 + 1.0;
    let s2 = params.y * 1.5 + 0.5;
    let s3 = params.z * 4.0 + 2.0;
    let feed = params.w * 0.5 + 0.5 + bass * 0.1 * sin(time * 0.3);

    let p1 = turing_pattern(uv, time, s1, feed);
    let p2 = turing_pattern(uv * 1.3 + vec2<f32>(0.4, -0.2), time * 0.8, s2, feed * 0.9);
    let p3 = turing_pattern(uv * 0.7 + vec2<f32>(-0.3, 0.5), time * 1.2, s3, feed * 1.1);

    let coarse = (p1.x * p2.y + p1.y * p2.x) * 2.0;
    let fine = (p2.x * p3.y + p2.y * p3.x) * 2.5;
    let micro = abs(p3.x - p3.y) * 3.0;
    return vec4<f32>(coarse, fine, micro, feed);
}
```

**Compatibility:** Requires `turing_pattern`

---

#### `iridescentSubstrate` — FBM-Driven Opal Iridescence
**Source:** `gen-opal-circuit.wgsl`

```wgsl
fn iridescentSubstrate(uv: vec2<f32>, time: f32, strength: f32) -> vec3<f32> {
    let n = fbm(uv * 5.0 + time * 0.1, 4);
    let angle = n * 6.28318;
    let r = 0.5 + 0.5 * cos(angle + 0.0);
    let g = 0.5 + 0.5 * cos(angle + 2.1);
    let b = 0.5 + 0.5 * cos(angle + 4.2);
    return vec3<f32>(r, g, b) * strength;
}
```

**Compatibility:** Requires `fbm`

---

#### `pulseBloom` — Expanding Radial Ring Glow
**Source:** `gen-bioreactor-bloom.wgsl`

```wgsl
fn pulseBloom(uv: vec2<f32>, time: f32, center: vec2<f32>, radius: f32, speed: f32) -> f32 {
    let d = length(uv - center);
    let ring = abs(d - radius * (0.7 + 0.3 * sin(time * speed)));
    return exp(-ring * ring * 80.0) * smoothstep(radius * 1.5, 0.0, d);
}
```

**Compatibility:** No dependencies

---

*End of Chunk Library - 75 Functions Documented*
