# Effect Shader Upgrade Swarm Analysis

> **Generated**: 2026-04-12  
> **Target**: 8 smallest effect shaders (69-74 lines)  
> **Goal**: Expand to 120-150 lines with advanced mathematical effects

---

## Executive Summary

Analyzed the **8 smallest effect shaders** (69-74 lines) and created detailed upgrade plans to transform them into sophisticated visual effects with:
- Professional blur kernels and bokeh simulation
- VHS/datamoshing/compression artifacts
- Lens distortion and chromatic dispersion models
- 3D perspective and atmospheric effects
- Parametric brush systems and slit-scan variations

---

## Shader Upgrade Matrix

| # | Shader | Category | Current | Target | +Lines | Complexity |
|---|--------|----------|---------|--------|--------|------------|
| 1 | radial-blur | post-processing | 69 | 145 | +76 | 🟡 Medium |
| 2 | chroma-shift-grid | distortion | 70 | 140 | +70 | 🟡 Medium |
| 3 | waveform-glitch | retro-glitch | 69 | 140 | +71 | 🔴 High |
| 4 | signal-noise | retro-glitch | 70 | 145 | +75 | 🔴 High |
| 5 | radial-rgb | distortion | 73 | 135 | +62 | 🟡 Medium |
| 6 | synthwave-grid-warp | retro-glitch | 74 | 145 | +71 | 🔴 High |
| 7 | temporal-slit-paint | artistic | 69 | 130 | +61 | 🟡 Medium-High |
| 8 | time-slit-scan | artistic | 69 | 140 | +71 | 🟡 Medium-High |

---

## Detailed Upgrade Plans

### 1. radial-blur.wgsl (69 lines)

**Current**: Simple 30-sample radial blur toward mouse

**5 Expansion Ideas**:
1. **Kernel-Based Weighted Blur** - Gaussian, tent, cubic kernels instead of box filter
2. **Bokeh Shape Simulation** - Hexagonal, star, anamorphic aperture shapes
3. **Depth-Aware Variable Blur** - Circle of confusion from depth texture
4. **Multi-Stop Color Curves** - Different blur radii per RGB channel
5. **Anamorphic Distortion** - Elliptical bokeh with directional streaking

**New Functions**:
```wgsl
fn gaussianWeight(t: f32, sigma: f32) -> f32
fn getBokehOffset(t: f32, angle: f32, shape: i32) -> vec2<f32>
fn calculateCoC(depth: f32, focalDepth: f32, maxBlur: f32) -> f32
fn sampleChromatic(uv: vec2<f32>, dir: vec2<f32>, strength: f32, samples: i32, chromaShift: f32) -> vec3<f32>
```

**RGBA Enhancement**:
- R: Variable radius (+10%)
- G: Baseline reference
- B: Variable radius (-10%)
- A: Proper alpha accumulation with kernel weight

---

### 2. chroma-shift-grid.wgsl (70 lines)

**Current**: Grid-based chromatic aberration with directional shift

**5 Expansion Ideas**:
1. **Multi-Axis Chromatic Separation** - Radial, rotational, zoom modes
2. **Temporal Animation Modes** - Pulse, breathe, glitch animations
3. **Multi-Stop Color Curves** - Spline-based RGB remapping
4. **Grid-Based Lens Distortion** - Barrel/pincushion per cell
5. **Depth-Aware Chromatic** - Stronger aberration on out-of-focus areas

**New Functions**:
```wgsl
fn getChromaticOffsets(uv: vec2<f32>, center: vec2<f32>, strength: f32, angle: f32, mode: i32) -> array<vec2<f32>, 3>
fn getAnimatedStrength(baseStrength: f32, time: f32, mode: i32, speed: f32) -> f32
fn distortByGrid(uv: vec2<f32>, cellCenter: vec2<f32>, strength: f32, gridUV: vec2<f32>) -> vec2<f32>
```

**RGBA Enhancement**:
- RGB: Configurable offsets per channel
- A: Grid-aware blending with smooth edges

---

### 3. waveform-glitch.wgsl (69 lines)

**Current**: Sine wave horizontal displacement with RGB split

**5 Expansion Ideas**:
1. **Multi-Frequency Wave Synthesis** - Sawtooth, square, triangle waves
2. **2D Perlin Noise Displacement Field** - Organic fluid distortions
3. **Block-Based Compression Artifacts** - MPEG macroblocking simulation
4. **VHS Tracking Error Simulation** - Horizontal sync jitter, creases
5. **Datamoshing Motion Vector Corruption** - Pixel smearing along edges

**New Functions**:
```wgsl
fn sawtoothWave(x: f32) -> f32
fn fbm(p: vec2<f32>, octaves: i32) -> f32
fn blockCorruption(uv: vec2<f32>, blockId: vec2<f32>, intensity: f32, time: f32) -> f32
fn vhsTracking(uv: vec2<f32>, time: f32, intensity: f32) -> vec2<f32>
fn estimateLumaGradient(uv: vec2<f32>) -> f32
```

**RGBA Enhancement**:
- RGB: Wave-displaced channels
- A: Glitch intensity transparency modulation

---

### 4. signal-noise.wgsl (70 lines)

**Current**: Scanline-based noise with horizontal shift

**5 Expansion Ideas**:
1. **Multi-Octave Perlin Noise** - fBM with temporal evolution
2. **VHS Head Switching + Tracking** - Periodic noise bands at bottom
3. **Block Compression Artifacts** - DCT ringing, mosquito noise
4. **Datamoshing Temporal Smearing** - Motion prediction error
5. **Multi-Directional Chromatic Aberration** - RGB with temporal delay

**New Functions**:
```wgsl
fn valueNoise(p: vec2<f32>) -> f32
fn fbmNoise(p: vec2<f32>, octaves: i32, lacunarity: f32, persistence: f32) -> f32
fn vhsHeadSwitch(uv: vec2<f32>, time: f32, intensity: f32) -> f32
fn dctBlockArtifact(uv: vec2<f32>, blockSize: f32, intensity: f32, time: f32) -> vec3<f32>
fn datamoshSmear(uv: vec2<f32>, intensity: f32, time: f32) -> vec4<f32>
```

**RGBA Enhancement**:
- RGB: YUV chroma noise processing
- A: Noise intensity-based transparency

---

### 5. radial-rgb.wgsl (73 lines)

**Current**: Radial chromatic aberration with mouse distance falloff

**5 Expansion Ideas**:
1. **Lens Distortion Model** - Barrel, pincushion, mustache distortion
2. **Wavelength-Dependent Dispersion** - Prism effect with 7 spectral samples
3. **Anamorphic Lens Flare** - Horizontal streaks, ghosting
4. **Depth-Aware Aberration** - Z-buffer differential sampling
5. **Volumetric Light Scattering** - God rays with exponential decay

**New Functions**:
```wgsl
fn lensDistort(uv: vec2<f32>, center: vec2<f32>, coeffs: vec3<f32>) -> vec2<f32>
fn wavelengthToRGB(wavelength: f32) -> vec3<f32>
fn sampleSpectral(uv: vec2<f32>, dispersion: f32, direction: vec2<f32>) -> vec3<f32>
fn applyVignette(color: vec3<f32>, uv: vec2<f32>, intensity: f32, roundness: f32) -> vec3<f32>
```

**RGBA Enhancement**:
- R: Spectral red (650nm)
- G: Spectral green (550nm)
- B: Spectral blue (450nm)
- A: Lens transmission factor

---

### 6. synthwave-grid-warp.wgsl (74 lines)

**Current**: 2D synthwave grid with mouse warp

**5 Expansion Ideas**:
1. **Perspective Projection Matrix** - True 3D floor grid
2. **Volumetric Glow & Atmospheric Scattering** - Mie scattering approximation
3. **Horizon Fog with Depth Cueing** - Exponential height fog
4. **Sun with Lens Flare** - Diffraction spikes, bloom
5. **Parallax Mountains** - SDF-based layered mountains

**New Functions**:
```wgsl
fn screenToWorld(uv: vec2<f32>, camY: f32, horizonY: f32) -> vec3<f32>
fn miePhase(cosTheta: f32, g: f32) -> f32
fn heightFog(distance: f32, height: f32, density: f32, falloff: f32) -> f32
fn renderSun(uv: vec2<f32>, sunPos: vec2<f32>, size: f32) -> vec3<f32>
fn mountainLayer(uv: vec2<f32>, layerZ: f32, offset: f32, sunPos: vec2<f32>) -> vec4<f32>
```

**RGBA Enhancement**:
- RGB: Sunset gradient + atmospheric scattering
- A: Layer blending factor

---

### 7. temporal-slit-paint.wgsl (69 lines)

**Current**: Mouse brush painting onto accumulating buffer

**5 Expansion Ideas**:
1. **Parametric Brush Shape System** - Superellipse, star, heart shapes
2. **Velocity-Aware Motion Smearing** - Anisotropic brush elongation
3. **Diffusion-Based Color Bleeding** - Laplacian diffusion sampling
4. **Temporal Noise Evolution** - 3D Perlin noise for jitter
5. **Layered Paint Physics** - Height-map based accumulation

**New Functions**:
```wgsl
fn brushMask(uv: vec2<f32>, center: vec2<f32>, size: f32, shapeType: i32, rotation: f32, softness: f32) -> f32
fn anisotropicBrush(uv: vec2<f32>, center: vec2<f32>, velocity: vec2<f32>, size: f32) -> f32
fn sampleWithDiffusion(uv: vec2<f32>, strength: f32) -> vec4<f32>
fn noise3D(p: vec3<f32>) -> f32
```

**RGBA Enhancement**:
- R/G/B: Color + diffusion influence
- A: Paint age/height accumulation

---

### 8. time-slit-scan.wgsl (69 lines)

**Current**: Vertical slit-scan with horizontal drift

**5 Expansion Ideas**:
1. **Multi-Slit Configuration** - 2-3 simultaneous slits
2. **Curved Parametric Slits** - Sine-wave, radial, spiral
3. **Polar Coordinate Drift** - Swirling time vortex
4. **Motion Vector Field Slits** - Optical flow alignment
5. **Slit Interpolation & Feathering** - Smoothstep feathering

**New Functions**:
```wgsl
fn sdSineSlit(uv: vec2<f32>, amplitude: f32, freq: f32, phase: f32, width: f32) -> f32
fn sdRadialSlit(uv: vec2<f32>, center: vec2<f32>, angle: f32, width: f32) -> f32
fn sdSpiralSlit(uv: vec2<f32>, center: vec2<f32>, turns: f32, width: f32) -> f32
fn cartesianToPolar(uv: vec2<f32>, center: vec2<f32>) -> vec2<f32>
fn slitBlendFactor(distance: f32, width: f32, feather: f32) -> f32
```

**RGBA Enhancement**:
- R/G/B: Color + time-warp tinting
- A: Frame timestamp / age

---

## Mathematical Concepts by Category

### Post-Processing & Blur
| Concept | Application |
|---------|-------------|
| Gaussian kernel | `exp(-0.5 * (t-0.5)² / σ²)` |
| Bokeh shapes | Polar coordinate modulation |
| Circle of Confusion | `abs(depth - focalDepth) * blurScale` |
| Anamorphic distortion | Non-uniform direction scaling |

### Glitch & Retro Effects
| Concept | Application |
|---------|-------------|
| Wave synthesis | Sawtooth, square, triangle functions |
| Block artifacts | Coordinate quantization |
| VHS tracking | Horizontal sync jitter |
| Datamoshing | Motion vector corruption |
| fBM noise | Multi-octave displacement |

### Lens & Optical Effects
| Concept | Application |
|---------|-------------|
| Lens distortion | `r * (1 + k₁r² + k₂r⁴ + k₃r⁶)` |
| Dispersion | Sellmeier equation approximation |
| Mie scattering | `(1-g²)/(1+g²-2g·cosθ)^1.5` |
| Vignetting | `1 - smoothstep(dist)` |

### 3D & Atmospheric
| Concept | Application |
|---------|-------------|
| Perspective projection | `worldPos → screenUV` |
| Height fog | `exp(-density * distance)` |
| Rayleigh scattering | `0.059 * (1 + cos²θ)` |
| Parallax scrolling | `layerDepth * offset` |

### Temporal & Painting
| Concept | Application |
|---------|-------------|
| SDF brushes | `length(p) - radius` |
| Anisotropic shapes | Velocity-aligned scaling |
| Laplacian diffusion | Neighbor sampling |
| Parametric curves | Sine, spiral, radial slits |

---

## Shared Function Library

All upgraded shaders should include:

```wgsl
// ═══ HASH & NOISE ═══
fn hash21(p: vec2<f32>) -> f32
fn hash11(p: f32) -> f32
fn valueNoise(p: vec2<f32>) -> f32
fn perlinNoise(p: vec2<f32>) -> f32
fn fbm(p: vec2<f32>, octaves: i32) -> f32

// ═══ COLOR UTILITIES ═══
fn rgbToLuma(rgb: vec3<f32>) -> f32
fn rgbToYuv(rgb: vec3<f32>) -> vec3<f32>
fn yuvToRgb(yuv: vec3<f32>) -> vec3<f32>
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32>

// ═══ SDF PRIMITIVES ═══
fn sdCircle(p: vec2<f32>, r: f32) -> f32
fn sdBox(p: vec2<f32>, b: vec2<f32>) -> f32
fn sdLine(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32
```

---

## Implementation Priority

| Priority | Shader | Reason |
|----------|--------|--------|
| P0 | radial-blur | Most requested, clear upgrade path |
| P0 | radial-rgb | Builds on existing chromatic work |
| P1 | waveform-glitch | High visual impact, retro trend |
| P1 | signal-noise | Pairs well with VHS aesthetic |
| P2 | synthwave-grid | Impressive 3D transformation |
| P2 | chroma-shift-grid | Grid effects popular |
| P3 | temporal-slit-paint | Artistic tools niche |
| P3 | time-slit-scan | Experimental/time-art niche |

---

## Expected Visual Improvements

| Shader | Before | After |
|--------|--------|-------|
| radial-blur | Boxy uniform blur | Bokeh lens simulation |
| chroma-shift-grid | Static RGB shift | Animated multi-mode |
| waveform-glitch | Clean sine wave | VHS/datamoshing chaos |
| signal-noise | Simple static | Authentic analog noise |
| radial-rgb | Basic RGB split | Spectral dispersion |
| synthwave-grid | Flat 2D grid | 3D horizon with fog |
| temporal-slit-paint | Circular brush | Calligraphic strokes |
| time-slit-scan | Vertical slit | Curved multi-slit |
