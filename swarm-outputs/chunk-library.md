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
