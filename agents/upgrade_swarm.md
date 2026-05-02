# WGSL Shader Upgrade Swarm Plan

> **Generated**: 2026-04-12  
> **Objective**: Identify and expand the smallest WGSL shaders with mathematical complexity, RGBA enhancements, and geometric sophistication

---

## Executive Summary

This plan identifies **30+ small WGSL shaders** (51-78 lines) and provides detailed expansion strategies using:
- **Mathematical curves** (Superellipses, Lissajous, Rose curves, Epicycloids)
- **Noise functions** (Perlin, Simplex, Gabor, Worley, FBM)
- **RGBA channel expansion** (beyond simple luminance alpha)
- **Geometric complexity** (SDFs, ray marching, conformal maps, topology)

---

## Phase 1: Quick Wins (Smallest Shaders)

### Tier 1: Ultra-Small (51-70 lines)

| Shader | Lines | Category | Current | Upgrade Strategy |
|--------|-------|----------|---------|------------------|
| `texture.wgsl` | 51 | image | Basic display | Procedural synthesis, edge detection, temporal filtering |
| `galaxy-compute.wgsl` | 65 | generative | 2D patterns | Ray marching, particle systems, orbital mechanics |
| `selective-color.wgsl` | 67 | image | Radial desat | Voronoi, SDF shapes, wave propagation, multi-focal |
| `sonic-distortion.wgsl` | 68 | distortion | Sine waves | Lissajous sources, FBM warping, Gabor anisotropy |
| `radial-blur.wgsl` | 69 | distortion | Linear blur | Fibonacci sampling, hypocycloid paths, depth-aware DoF |
| `temporal-slit-paint.wgsl` | 69 | artistic | Brush paint | Reaction-diffusion, velocity brush, flow fields |
| `time-slit-scan.wgsl` | 69 | artistic | Slit scan | Wave equations, advection, multi-axis, spectral decomposition |
| `waveform-glitch.wgsl` | 69 | glitch | Sine displacement | Block glitch, VHS tracking, multi-octave waves |
| `alucinate.wgsl` | 70 | distortion | UV warping | Reaction-diffusion, fluid sim, IFS, conformal maps |
| `signal-noise.wgsl` | 70 | glitch | Scanline noise | Gradient noise, CRT effects, blue noise, tape degradation |

### Tier 2: Small (71-78 lines)

| Shader | Lines | Category | Upgrade Focus |
|--------|-------|----------|---------------|
| `hyper-chromatic-delay.wgsl` | 71 | artistic | Multi-tap filter, spectral dispersion, lens distortion |
| `mosaic-reveal.wgsl` | 71 | distortion | Hex/Voronoi grids, block animation, flood fill |
| `neon-cursor-trace.wgsl` | 72 | artistic | Multi-point trail, spring physics, particle system |
| `pixel-repel.wgsl` | 73 | distortion | Multi-point Lissajous, curl noise, superellipse masks |
| `polka-dot-reveal.wgsl` | 73 | distortion | Variable dot patterns, animated transitions |
| `radial-rgb.wgsl` | 73 | distortion | Rose directions, spectral shifts, animated centers |
| `kaleidoscope.wgsl` | 74 | geometric | Rose segments, FBM mirrors, epicycloid patterns |
| `sonar-reveal.wgsl` | 74 | artistic | Sweep animation, echo returns, Doppler, interference |
| `echo-trace.wgsl` | 75 | artistic | Multi-octave, structure tensor, phasing |

---

## Phase 2: Mathematical Function Library

### Core Geometric Functions (Add to all upgraded shaders)

```wgsl
// ═══════════════════════════════════════════════════════════════════
//  GEOMETRIC COMPLEXITY FUNCTION LIBRARY
// ═══════════════════════════════════════════════════════════════════

// ─── Superellipse ───
fn superellipseMask(d: vec2<f32>, a: f32, b: f32, n: f32) -> f32 {
    let xn = pow(abs(d.x) / max(a, 0.001), n);
    let yn = pow(abs(d.y) / max(b, 0.001), n);
    return 1.0 - smoothstep(0.8, 1.0, xn + yn);
}

// ─── Lissajous ───
fn lissajousOffset(t: f32, A: f32, B: f32, a: f32, b: f32, delta: f32) -> vec2<f32> {
    return vec2<f32>(A * sin(a * t + delta), B * sin(b * t));
}

// ─── Rose Curve ───
fn roseModulation(angle: f32, n: f32, a: f32) -> f32 {
    return a * abs(cos(n * angle * 0.5));
}

// ─── Epicycloid ───
fn epicycloidPoint(t: f32, R: f32, r: f32) -> vec2<f32> {
    return vec2<f32>(
        (R + r) * cos(t) - r * cos((R + r) / max(r, 0.001) * t),
        (R + r) * sin(t) - r * sin((R + r) / max(r, 0.001) * t)
    );
}

// ─── Hypocycloid ───
fn hypocycloidPoint(t: f32, R: f32, r: f32) -> vec2<f32> {
    let k = R / max(r, 0.001);
    return vec2<f32>(
        (R - r) * cos(t) + r * cos((R - r) / max(r, 0.001) * t),
        (R - r) * sin(t) - r * sin((R - r) / max(r, 0.001) * t)
    );
}

// ─── Fibonacci Disk Sampling ───
fn fibonacciDiskSample(i: i32, n: i32) -> vec2<f32> {
    let golden = 2.39996322972865332;
    let theta = f32(i) * golden;
    let r = sqrt(f32(i)) / sqrt(f32(max(n, 1)));
    return vec2<f32>(cos(theta), sin(theta)) * r;
}

// ─── Rotation ───
fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}
```

### Noise Function Library

```wgsl
// ─── Hash Functions ───
fn hash11(p: f32) -> f32 { return fract(sin(p) * 43758.5453123); }
fn hash12(p: vec2<f32>) -> f32 { 
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); 
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    return fract(sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), 
                                dot(p, vec2<f32>(269.5, 183.3)))) * 43758.5453);
}
fn hash33(p: vec3<f32>) -> vec3<f32> {
    var n = sin(dot(p, vec3<f32>(127.1, 311.7, 74.7)));
    return fract(vec3<f32>(n) * vec3<f32>(43758.5453, 28001.8384, 50849.4141));
}

// ─── Value Noise ───
fn valueNoise2D(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)), 
                   hash12(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash12(i + vec2<f32>(0.0, 1.0)), 
                   hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// ─── Perlin-style Gradient Noise ───
fn gradientNoise2D(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    
    let h00 = hash12(i + vec2<f32>(0.0, 0.0));
    let h10 = hash12(i + vec2<f32>(1.0, 0.0));
    let h01 = hash12(i + vec2<f32>(0.0, 1.0));
    let h11 = hash12(i + vec2<f32>(1.0, 1.0));
    
    let g00 = vec2<f32>(cos(h00 * 6.28), sin(h00 * 6.28));
    let g10 = vec2<f32>(cos(h10 * 6.28), sin(h10 * 6.28));
    let g01 = vec2<f32>(cos(h01 * 6.28), sin(h01 * 6.28));
    let g11 = vec2<f32>(cos(h11 * 6.28), sin(h11 * 6.28));
    
    let d00 = dot(g00, f - vec2<f32>(0.0, 0.0));
    let d10 = dot(g10, f - vec2<f32>(1.0, 0.0));
    let d01 = dot(g01, f - vec2<f32>(0.0, 1.0));
    let d11 = dot(g11, f - vec2<f32>(1.0, 1.0));
    
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(d00, d10, u.x), mix(d01, d11, u.x), u.y) * 0.5 + 0.5;
}

// ─── FBM (Fractal Brownian Motion) ───
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var pos = p;
    for(var i: i32 = 0; i < octaves; i = i + 1) {
        v = v + a * gradientNoise2D(pos);
        pos = rot * pos * 2.0 + 100.0;
        a = a * 0.5;
    }
    return v;
}

fn fbm2(p: vec2<f32>, octaves: i32) -> vec2<f32> {
    return vec2<f32>(fbm(p, octaves), fbm(p + 100.0, octaves));
}

// ─── Gabor Noise ───
fn gaborNoise(uv: vec2<f32>, dir: vec2<f32>, freq: f32, bandwidth: f32) -> f32 {
    let phase = dot(uv, dir) * freq;
    let envelope = exp(-bandwidth * dot(uv, uv));
    return cos(phase) * envelope;
}

// ─── Curl Noise ───
fn curlNoise(uv: vec2<f32>, eps: f32) -> vec2<f32> {
    let n = gradientNoise2D(uv);
    let nx = gradientNoise2D(uv + vec2<f32>(eps, 0.0));
    let ny = gradientNoise2D(uv + vec2<f32>(0.0, eps));
    return vec2<f32>((ny - n) / eps, -(nx - n) / eps);
}
```

---

## Phase 3: Detailed Shader Upgrade Plans

### 1. SONIC-DISTORTION.WGSL → "Superellipse Sonic Chaos"

**Current**: 68 lines - Simple sine wave distortion

**Expansion Ideas**:
1. **Superellipse Masking Zones** - Replace circular radius with shape-morphing superellipse
2. **Lissajous Wave Interference** - Add orbiting Lissajous curve-based secondary wave sources
3. **Epicycloid Ripple Sources** - Multiple orbiting ripple sources following epicycloid paths
4. **FBM Domain Warping** - Domain-warp sonic waves through multi-octave noise
5. **Rose Curve Modulation** - Modulate wave amplitude by rose curve pattern
6. **Gabor Noise Anisotropy** - Directionally-oriented noise streaking
7. **Alpha-Ghosted Echo Trails** - Temporal feedback with RGBA echo trails

**New Functions to Add**:
```wgsl
fn superellipseMask(d: vec2<f32>, a: f32, b: f32, n: f32) -> f32
fn lissajousOffset(t: f32, A: f32, B: f32, a: f32, b: f32, delta: f32) -> vec2<f32>
fn fbmWarp(p: vec2<f32>, time: f32) -> vec2<f32>
fn roseModulation(angle: f32, n: f32, a: f32) -> f32
```

**RGBA Expansion**:
```wgsl
let alpha = 0.5 + 0.5 * abs(wave) * mask * (1.0 - dist/radius);
// Alpha varies with wave intensity for ghost-like edges
```

**Target Line Count**: ~150-200 lines

---

### 2. RADIAL-BLUR.WGSL → "Fibonacci Hypocycloid Blur"

**Current**: 69 lines - Linear radial sampling

**Expansion Ideas**:
1. **Hypocycloid Sampling Paths** - Sample along hypocycloid curves for swirling blur
2. **Superellipse Falloff Profile** - Squircle-shaped blur concentration
3. **Fibonacci Sphere Sampling** - Golden ratio distributed samples
4. **Perlin Noise Offset Jitter** - Organic blur variation
5. **Epicycloid Rotation Centers** - Multiple rotating focal points
6. **Depth-Aware Variable Blur** - Bokeh-like depth of field
7. **Anisotropic Directional Blur** - Lissajous-inspired directional weighting

**New Functions**:
```wgsl
fn fibonacciDiskSample(i: i32, n: i32) -> vec2<f32>
fn hypocycloidOffset(t: f32, R: f32, r: f32) -> vec2<f32>
fn perlinNoise(p: vec2<f32>) -> f32
```

**RGBA Expansion**:
```wgsl
let radialAlpha = 1.0 - smoothstep(0.0, radius, dist);
let accumulatedAlpha = sampleColor.a * radialAlpha * weight;
// Premultiplied alpha for transparency accumulation
```

---

### 3. KALEIDOSCOPE.WGSL → "Rose FBM Kaleidoscope"

**Current**: 74 lines - Simple angular mirroring

**Expansion Ideas**:
1. **Rose Curve Segment Boundaries** - Petal-shaped mirror segments
2. **Lissajous Displacement Field** - Wobbling, breathing effect
3. **Epicycloid Inner Patterns** - Spirograph patterns inside segments
4. **FBM Turbulent Mirror** - Organic liquid-like distortions
5. **Superellipse Zoom Windows** - Diamond/squircle magnified regions
6. **Hypocycloid Outer Frame** - Star/flower-shaped aperture
7. **Gabor Anisotropic Segments** - Textured, fabric-like segments

**RGBA Expansion**:
```wgsl
let segmentEdge = abs(fract(angle / segmentAngle) * 2.0 - 1.0);
let edgeGlow = smoothstep(0.9, 1.0, segmentEdge);
let alpha = 0.8 + edgeGlow * 0.2;
// Stained-glass effect with gold edge highlighting
```

---

### 4. SELECTIVE-COLOR.WGSL → "Voronoi Multi-Focal Selective"

**Current**: 67 lines - Single mouse-point desaturation

**Expansion Ideas**:
1. **Voronoi-Based Multi-Focal** - Dynamic cell centers for organic regions
2. **Chromatic Aberration Reveal** - RGB separation at boundaries
3. **Fractal Noise Masking** - fBm for irregular organic shapes
4. **Polar Coordinate Transform** - Angular sector reveals
5. **SDF Shape Library** - Stars, hearts, hexagons as masks
6. **Wave Propagation Reveal** - Ripple propagation from clicks
7. **Depth-Aware Edge Detection** - Sobel edge-aware selective color

**New Functions**:
```wgsl
fn voronoi_selective(uv: vec2<f32>, time: f32) -> f32
fn sdf_star(p: vec2<f32>, points: f32, inner_r: f32, outer_r: f32) -> f32
fn sdf_heart(p: vec2<f32>) -> f32
fn fbm_noise(p: vec2<f32>, octaves: i32) -> f32
```

---

### 5. TEMPORAL-SLIT-PAINT.WGSL → "Reaction-Diffusion Painter"

**Current**: 69 lines - Simple brush painting

**Expansion Ideas**:
1. **Velocity-Aware Brush** - Dynamic properties based on speed
2. **Gray-Scott Reaction-Diffusion** - Turing patterns in painted regions
3. **Spectral Brush** - Multi-scale frequency decomposition
4. **Physics-Based Particle Brush** - Simulated particles emitted from brush
5. **Neural-Style Flow Fields** - Oriented strokes with flow field
6. **Multi-Layer Painting** - Separate layers with blend modes
7. **Temporal Echo Trails** - Rainbow trail of previous positions

**New Functions**:
```wgsl
fn gray_scott_step(uv: vec2<i32>, feed: f32, kill: f32, du: f32, dv: f32) -> vec2<f32>
fn flow_field(uv: vec2<f32>, time: f32) -> f32
fn sd_oriented_box(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, th: f32) -> f32
```

---

### 6. TIME-SLIT-SCAN.WGSL → "Wave-Advection Slit Scanner"

**Current**: 69 lines - Horizontal drift only

**Expansion Ideas**:
1. **Multi-Axis Slit Scan** - Vertical, radial, angular dimensions
2. **Wave-Propagating Slit** - Wave equation on slit position
3. **Turbulent Time Distortion** - Fluid-like advection to time buffer
4. **Phase-Synchronized Multi-Slit** - Harmonic relationships
5. **Spectral Slit** - Different temporal frequencies per band
6. **Slit with Feedback Displacement** - Luminance-driven warp
7. **Interlaced Temporal Offset** - Odd/even line delays

---

### 7. WAVEFORM-GLITCH.WGSL → "Multi-Octave Block Glitch"

**Current**: 69 lines - Simple sine wave displacement

**Expansion Ideas**:
1. **Multi-Octave Wave Interference** - Harmonic frequencies for organic waves
2. **Digital Block Glitch** - Horizontal slice displacement
3. **VHS Tracking Errors** - Periodic tracking distortion
4. **Signal Degradation** - Temporal analog noise patterns
5. **Bayer Dithering Overlay** - Retro matrix dithering
6. **Harmonic Oscillator Movement** - Coupled oscillators
7. **Fourier Transform Patterns** - Frequency-domain visualization

---

### 8. SIGNAL-NOISE.WGSL → "Gradient Gabor Noise"

**Current**: 70 lines - 1D hash noise

**Expansion Ideas**:
1. **Gradient Noise (Perlin)** - 2D gradient-based coherent noise
2. **Gabor Noise** - Oriented anisotropic patterns
3. **Pixel Sort Glitch** - Algorithmic pixel sorting effect
4. **CRT Scanline + Shadow Mask** - Authentic CRT artifacts
5. **Cellular Automata** - CA-driven noise patterns
6. **Blue Noise** - High-quality dithering patterns
7. **Tape Degradation** - Magnetic tape deterioration simulation

---

### 9. HYPER-CHROMATIC-DELAY.WGSL → "Spectral Multi-Tap Echo"

**Current**: 71 lines - Simple RGB offset with trails

**Expansion Ideas**:
1. **Multi-Tap Temporal Filter** - Weighted average of multiple frames
2. **Motion Blur Trails** - Direction-aware temporal blur
3. **Spectral Dispersion** - Wavelength-dependent refraction (7 samples)
4. **Fractal Feedback** - Mandelbrot-inspired feedback mask
5. **Lens Distortion** - Optical per-channel distortion
6. **Visual Reverb** - Audio-reverb inspired echoes
7. **Time-Warp Feedback** - Non-linear temporal sampling

---

### 10. NEON-CURSOR-TRACE.WGSL → "Particle Physics Trace"

**Current**: 72 lines - Simple distance-based trail

**Expansion Ideas**:
1. **Multi-Point Trail History** - Persistent ring buffer of positions
2. **Spring-Mass Cursor Physics** - Physical trail simulation
3. **Neon Glow with Gaussian** - Multi-sample glow approximation
4. **Audio-Reactive Particles** - Spawn particles with bass
5. **Electric Arc Effects** - Tesla coil visualization
6. **Volumetric Light Rays** - God rays from cursor
7. **Phosphor Persistence** - RGB phosphor decay simulation

---

### 11. GALAXY-COMPUTE.WGSL → "Volumetric Spiral Galaxy"

**Current**: 65 lines - 2D color patterns

**Expansion Ideas**:
1. **Ray Marched Spiral Galaxy** - Logarithmic spiral SDF with density integration
2. **Procedural Nebula Clouds** - 3D Perlin-Worley hybrid
3. **Stellar Particle System** - Orbital mechanics with epicyclic motion
4. **Gravitational Lensing** - Schwarzschild black hole simulation
5. **Hyperbolic Tiling** - Poincaré disk exotic formations
6. **Kelvin-Helmholtz Instability** - Procedural dust lane patterns
7. **Mandelbrot-Julia Hybrid** - Fractal structures in arms

**New Functions**:
```wgsl
fn spiralArmSDF(p: vec3<f32>, armCount: f32, tightness: f32) -> f32
fn simplex3D(p: vec3<f32>) -> f32
fn worley3D(p: vec3<f32>) -> vec2<f32>
fn galaxyDensity(p: vec3<f32>, time: f32) -> f32
fn orbitalVelocity(r: f32, v_max: f32, r_core: f32) -> f32
```

**RGBA Expansion**:
```wgsl
// R: Stellar emission (hot gas)
// G: Dust scattering
// B: Synchrotron radiation
// A: Optical depth / density
let tau = integrateDensity(rayOrigin, rayDir);
return vec4<f32>(emission, tau);
```

---

### 12. ALUCINATE.WGSL → "Reaction-Diffusion Psychedelia"

**Current**: 70 lines - Basic UV warping

**Expansion Ideas**:
1. **Gray-Scott Reaction-Diffusion** - Turing patterns
2. **Domain Warping with FBM** - Recursive organic distortion
3. **Fluid Dynamics** - Stable Navier-Stokes simulation
4. **Kaleidoscopic IFS** - Fractal transformations
5. **Conformal Mapping** - Complex function warping
6. **Lyapunov Fractals** - Chaos-based patterns
7. **Phase-Amplitude Modulation** - FM synthesis visualization

---

### 13. TEXTURE.WGSL → "Procedural Texture Analyzer"

**Current**: 51 lines - Basic pass-through

**Expansion Ideas**:
1. **Procedural Synthesis Suite** - Gabor, spot, weave patterns
2. **Multi-Scale Detail Enhancement** - Bilateral filter, unsharp mask
3. **Structure-from-Motion Depth** - Optical flow, depth estimation
4. **Material Recognition** - Segment by material type
5. **Frequency Domain Processing** - Gabor filter bank
6. **Super-Resolution** - Gradient profile reconstruction
7. **Temporal Consistency** - Motion-compensated filtering

---

## Phase 4: RGBA Encoding Strategies

### Standard RGBA Channel Allocation

| Channel | Typical Use | Advanced Use |
|---------|-------------|--------------|
| **R** | Color Red | Edge response, X-distortion, emission |
| **G** | Color Green | Texture roughness, temporal phase |
| **B** | Color Blue | Frequency content, stability measure |
| **A** | Luminance alpha | Confidence, optical depth, age, quality |

### Shader-Specific RGBA Schemes

**Distortion Shaders** (sonic, radial, pixel-repel):
```wgsl
R = abs(warp_offset.x) * 5        // X distortion magnitude
G = fract(time * 0.1 + warp)      // Temporal phase
B = fbm(warped_uv * 10) * PI      // Frequency modulation  
A = velocityAlpha(displacement)   // Motion blur alpha
```

**Artistic Shaders** (echo, neon, slit):
```wgsl
R = emission_strength               // Hot regions
G = age / max_age                   // Temporal age
B = stability_metric                // Temporal consistency
A = focusMeasure * edgeStrength     // Quality/confidence
```

**Reveal Shaders** (selective, mosaic, sonar):
```wgsl
R = reveal_mask                     // Reveal area
G = edge_distance                   // Distance to boundary
B = depth_factor                    // Depth influence
A = reveal_age * confidence         // Temporal accumulation
```

---

## Phase 5: Implementation Roadmap

### Week 1: Foundation
- [ ] Implement shared mathematical function library
- [ ] Add noise functions (value, gradient, FBM, Gabor)
- [ ] Add geometric primitives (superellipse, Lissajous, rose)

### Week 2: Distortion Shader Upgrades
- [ ] Upgrade sonic-distortion with superellipse + Lissajous
- [ ] Upgrade radial-blur with Fibonacci + hypocycloid
- [ ] Upgrade kaleidoscope with rose + FBM

### Week 3: Artistic Shader Upgrades  
- [ ] Upgrade temporal-slit-paint with reaction-diffusion
- [ ] Upgrade echo-trace with structure tensor
- [ ] Upgrade neon-cursor with particle system

### Week 4: Advanced Generative
- [ ] Upgrade galaxy-compute with ray marching
- [ ] Upgrade alucinate with fluid dynamics
- [ ] Upgrade texture with procedural synthesis

### Week 5: RGBA Integration
- [ ] Implement per-shader RGBA encoding strategies
- [ ] Add alpha-aware compositing to renderer
- [ ] Test blending modes for new alpha types

---

## Appendix A: Wolfram Alpha Mathematical References

### Superellipse
```
Cartesian: |x/a|^n + |y/b|^n = 1
Parametric: x = a * sign(cos θ) * |cos θ|^(2/n)
            y = b * sign(sin θ) * |sin θ|^(2/n)
```

### Lissajous Curves
```
x = A sin(a*t + δ)
y = B sin(b*t)
```

### Rose Curves (Rhodonea)
```
Polar: r = a * cos(n*θ)
Parametric: x = a cos(t) sin(n*t)
            y = a sin(t) sin(n*t)
Area: (πa²)/2 for even n, (πa²)/4 for odd n
```

### Epicycloid
```
x = (R+r)cos(t) - r*cos((R+r)/r*t)
y = (R+r)sin(t) - r*sin((R+r)/r*t)
```

### Hypocycloid
```
x = (R-r)cos(t) + r*cos((R-r)/r*t)
y = (R-r)sin(t) - r*sin((R-r)/r*t)
```

---

## Appendix B: Shader Upgrade Priority Matrix

| Priority | Shader | Effort | Impact | Reason |
|----------|--------|--------|--------|--------|
| P0 | galaxy-compute | High | Very High | Foundational generative shader |
| P0 | sonic-distortion | Medium | High | Popular effect, easy wins |
| P0 | alucinate | High | Very High | Flagship psychedelic effect |
| P1 | kaleidoscope | Medium | High | Visual impact strong |
| P1 | echo-trace | Medium | High | Temporal effects popular |
| P1 | neon-cursor-trace | Medium | High | Interactive appeal |
| P2 | radial-blur | Low | Medium | Utility effect |
| P2 | selective-color | Medium | Medium | Good for tutorials |
| P2 | waveform-glitch | Medium | Medium | Glitch aesthetic |
| P3 | signal-noise | Low | Medium | Niche effect |
| P3 | texture | High | Medium | Infrastructure shader |

---

## Conclusion

This upgrade plan provides a comprehensive roadmap for evolving 30+ small WGSL shaders from simple 50-70 line implementations to sophisticated 150-300 line visual effects. The key strategies are:

1. **Mathematical Depth**: Incorporate curves from Wolfram Alpha (superellipses, Lissajous, roses)
2. **Noise Sophistication**: Upgrade from simple hash to Perlin, Gabor, Worley, FBM
3. **RGBA Intelligence**: Encode meaningful data beyond luminance in alpha channel
4. **Geometric Complexity**: Add SDFs, ray marching, conformal maps, topology

**Estimated Total Impact**: 30+ upgraded shaders, ~5,000 new lines of WGSL code, significant visual quality improvement across the entire shader library.

---

## Appendix C: External Project Shader Compatibility

> **Scope:** The following external projects have weather/lighting shaders that should be upgraded and kept compatible with the image_video_effects WGSL compute pipeline so they can share binding layouts, uniform structs, and compositor integration.

| Project | Shader(s) | Current Format | Compatibility Action |
|---------|-----------|----------------|----------------------|
| `webgpu_streetview` | `weather-post.wgsl` | WGSL render pipeline | Convert to compute pipeline with standard 13-binding header; map `WeatherParams` → `extraBuffer` |
| `weather_clock` | `shaders.js` (rain, splash, clouds, stars) | GLSL (Three.js) | Port to WGSL compute shaders using standard header; keep GLSL for WebGL fallback |
| `harborglow` | `lightShowNodes.ts` (god rays) | GLSL/TSL (Three.js) | Port to WGSL compute volumetric shaft shader using standard header; keep GLSL for WebGL fallback |

### Binding Standard for Ported Shaders

All ported shaders MUST use the exact 13-binding header:

```wgsl
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};
```

### Parameter Overflow Strategy

Project-specific parameters that exceed the 3 vec4 uniform capacity (e.g., `WeatherParams` with 40 fields) MUST be packed into `extraBuffer` (`@binding(10)`) as a structured float array. **Do NOT extend the `Uniforms` struct**, as this breaks cross-shader compatibility.

**Example `extraBuffer` layout for weather params:**
```wgsl
// extraBuffer[0..39] = WeatherParams mapping
// 0:  vibrance          1:  saturation        2:  contrast
// 3:  exposure          4:  temperature       5:  tint
// 6:  time              7:  rainIntensity     8:  snowIntensity
// 9:  wind              10: speed             11: nightIntensity
// 12: headlightsOn      13: highBeam          14: headlightHeading
// 15: headlightPitch    16: domeLightOn       17: domeLightIntensity
// 18: sunAzimuth        19: sunAltitude       20: moonAzimuth
// 21: moonAltitude      22: fogIntensity      23: fogDensity
// 24: fogHeight         25: fogColorIndex     26: lightShaftsIntensity
// 27: heatShimmerIntensity  28: lensFlareIntensity  29: chromaticAberration
// 30: dustIntensity     31: humidityHaze      32: shaderEffectsEnabled
// 33: cameraHeading     34: cameraPitch       35: sunrise
// 36: anamorphicStreak
```

### Re-use Existing Shaders

Before writing new weather shaders from scratch, check the image_video_effects library for existing equivalents and extend those:

- **Rain:** `rain.wgsl`, `cyber-rain.wgsl`, `cyber-rain-interactive.wgsl`, `gen_fluffy_raincloud.wgsl`, `rain-lens-wipe.wgsl`, `raindrop-ripples.wgsl`, `rain-ripples.wgsl`
- **Snow:** `snow.wgsl`, `frost-reveal.wgsl`, `frosty-window.wgsl`, `crystal-freeze.wgsl`
- **Fog:** `atmos-fog-volumetric.wgsl`, `atmos_volumetric_fog.wgsl`, `alpha-depth-fog-volumetric.wgsl`, `digital-haze.wgsl`, `vaporwave-horizon.wgsl`
- **God rays / Light shafts:** `volumetric-god-rays.wgsl`, `volumetric-light-shafts.wgsl`, `divine-light.wgsl`, `lighthouse-reveal.wgsl`
- **Dust / Particles:** `pixel-sand.wgsl`, `cymatic-sand.wgsl`, `particle-swarm.wgsl`
- **Lens effects:** `lens-flare-brush.wgsl`, `dynamic-lens-flares.wgsl`, `glass-lens.wgsl`
- **Night / Stars:** `night-vision-scope.wgsl`, `gen-nebula-light-trail-swarm.wgsl`

### Porting Roadmap

1. **Phase A (Immediate):** Port `webgpu_streetview/weather-post.wgsl` → `weather-post-compute.wgsl` using compute pipeline + extraBuffer mapping.
2. **Phase B (Next):** Port `weather_clock` rain/snow/splash to procedural compute shaders; keep GLSL for WebGL fallback.
3. **Phase C (Future):** Port `harborglow` god rays to compute volumetric post-process; keep GLSL/TSL for WebGL fallback.
