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

## Common Foundations

All upgraded shaders should start with a shared utility module (~30 lines). Copy-paste it at the top of each file (or import it as a separate WGSL module if your runtime supports it).

```wgsl
// ──────────────────────────────────────────────────────────────
//  🎛️  COMMON UTILS – 30 lines (≈ 1 KB)
// ──────────────────────────────────────────────────────────────

// ── Hash & Noise ─────────────────────────────────────────────
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}
fn hash11(p: f32) -> f32 {
    return fract(sin(p * 12.9898) * 43758.5453);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);          // smoothstep
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i = i + 1) {
        sum = sum + amp * valueNoise(p * freq);
        freq = freq * 2.0;
        amp = amp * 0.5;
    }
    return sum;
}

// ── Color Conversions ───────────────────────────────────────
fn rgbToLuma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}
fn rgbToYuv(rgb: vec3<f32>) -> vec3<f32> {
    let y = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b;
    let u = -0.14713 * rgb.r - 0.28886 * rgb.g + 0.436 * rgb.b;
    let v = 0.615 * rgb.r - 0.51499 * rgb.g - 0.10001 * rgb.b;
    return vec3<f32>(y, u, v);
}
fn yuvToRgb(yuv: vec3<f32>) -> vec3<f32> {
    let r = yuv.x + 1.13983 * yuv.z;
    let g = yuv.x - 0.39465 * yuv.y - 0.58060 * yuv.z;
    let b = yuv.x + 2.03211 * yuv.y;
    return vec3<f32>(r, g, b);
}
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let c = hsv.z * hsv.y;
    let h = hsv.x * 6.0;
    let x = c * (1.0 - abs(fract(h) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else              { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(hsv.z - c);
}

// ── SDF Primitives ────────────────────────────────────────
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
    return length(p) - r;
}
fn sdBox(p: vec2<f32>, b: vec2<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}
fn sdLine(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}
```

**Why?**
- Hash & fBM give you deterministic "randomness" that works on every frame without a CPU RNG.
- Color utilities let you switch between YUV (good for VHS-style chroma noise) and HSV (nice for UI sliders).
- SDF primitives are the building blocks for brush masks, slit-shapes, and bokeh apertures.

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

### 1. radial-blur.wgsl (69 lines) → 145 lines

**Current**: Simple 30-sample radial blur toward mouse

**Goal**: From a simple 30-sample radial blur → a full bokeh-aware, depth-aware, chromatic-dispersion blur.

**Architectural Overview**

| Stage | Function | Description |
|-------|----------|-------------|
| 1️⃣ | `gaussianWeight(t, sigma)` | Returns Gaussian kernel weight for sample index t∈[0,1]. |
| 2️⃣ | `getBokehOffset(t, angle, shape)` | Generates a 2-D offset for the current sample based on the selected aperture shape (circle, hexagon, 6-point star). |
| 3️⃣ | `calculateCoC(depth, focalDepth, maxBlur)` | Circle-of-confusion from a depth texture (optional). |
| 4️⃣ | `sampleChromatic(uv, dir, strength, samples, chromaShift)` | Performs the weighted loop, splitting RGB channels with independent radii. |
| 5️⃣ | `applyVignette(color, uv, vignetteStrength)` | Optional final vignette to keep the effect subtle at the edges. |

**Sample Implementation (≈ 120 lines)**

```wgsl
// ── GAUSSIAN KERNEL (pre‑compute 1‑D weights) ─────────────────
fn gaussianWeight(t: f32, sigma: f32) -> f32 {
    // 0 ≤ t ≤ 1  →  -1 … +1  (centered)
    let x = (t - 0.5) * 2.0;
    return exp(-0.5 * (x * x) / (sigma * sigma));
}

// ── BOKEH SHAPE OFFSETS ───────────────────────────────────────
fn getBokehOffset(t: f32, angle: f32, shape: i32) -> vec2<f32> {
    // map t → polar radius (0‑1) with jitter
    let radius = sqrt(t);
    // 6‑point star / hexagon uses angular quantisation
    var a = angle + 2.0 * PI * t;
    if (shape == 1) { // hexagon
        a = round(a / (PI/3.0)) * (PI/3.0);
    } else if (shape == 2) { // star
        let seg = floor(a / (PI/3.0));
        a = mix(seg * (PI/3.0), (seg + 0.5) * (PI/3.0), smoothstep(0.0, 0.5, fract(a/(PI/3.0))));
    }
    return vec2<f32>(cos(a), sin(a)) * radius;
}

// ── CIRCLE OF CONFUSION (depth‑aware) ────────────────────────
fn calculateCoC(depth: f32, focalDepth: f32, maxBlur: f32) -> f32 {
    // linearize depth if needed; here we assume already linear [0‑1]
    let coc = abs(depth - focalDepth) * maxBlur;
    return clamp(coc, 0.0, maxBlur);
}

// ── MAIN SAMPLING LOOP ────────────────────────────────────────
fn sampleChromatic(uv: vec2<f32>, dir: vec2<f32>, strength: f32,
                  samples: i32, chromaShift: f32) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    var weightSum = 0.0;
    // pre‑compute angle for the radial direction
    let baseAngle = atan2(dir.y, dir.x);
    for (var i = 0; i < samples; i = i + 1) {
        let t = f32(i) / f32(samples - 1); // 0‑1
        let w = gaussianWeight(t, u.zoom_params.x); // sigma via param
        // bokeh offset (shape + jitter)
        let off = getBokehOffset(t, baseAngle, i32(u.zoom_params.y)); // shape via param
        // depth‑aware radius
        let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + off * strength, 0.0).r;
        let radius = calculateCoC(depth, u.zoom_params.z, u.zoom_params.w); // focalDepth, maxBlur via params
        let sampleUV = uv + off * radius;
        // split‑RGB chromatic shift
        let r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(chromaShift, 0.0), 0.0).r;
        let g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(chromaShift, 0.0), 0.0).b;
        col = col + vec3<f32>(r,g,b) * w;
        weightSum = weightSum + w;
    }
    return col / weightSum;
}

// ── VIGNETTE ───────────────────────────────────────────────────
fn applyVignette(color: vec3<f32>, uv: vec2<f32>, strength: f32) -> vec3<f32> {
    let d = length(uv - vec2<f32>(0.5));
    let v = smoothstep(0.5, 0.5 - strength, d);
    return color * v;
}

// ── ENTRY POINT ───────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let uv = vec2<f32>(global_id.xy) / vec2<f32>(u.config.z, u.config.w);
    // direction from centre to current pixel (used for radial blur)
    let dir = uv - vec2<f32>(0.5);
    let blurred = sampleChromatic(uv, dir, 0.05, 32, 0.003);
    let final = applyVignette(blurred, uv, 0.3);
    textureStore(writeTexture, global_id.xy, vec4<f32>(final, 1.0));
}
```

**Line count** – ~115 lines (including the shared utilities). Add a few UI-binding lines and you land at ≈145.

**Performance Tips**

| Tip | Reason |
|-----|--------|
| Use `for (var i = 0; i < 32; i++)` – 32 samples is a sweet spot on modern GPUs. | Balances quality and ALU cost. |
| Store `sigma` and `maxBlur` as float uniforms, not per-pixel calculations. | Avoids redundant math in the hot loop. |
| If you have a depth texture, sample it once per iteration (as shown). If you don’t need depth-aware blur, replace the depth sample with a constant radius to save a texture fetch. | Reduces bandwidth when depth isn’t needed. |
| Compile the shader with `@workgroup_size(16,16,1)` to keep the compute pass GPU-friendly. | Matches the project standard. |

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

### 3. waveform-glitch.wgsl (69 lines) → 140 lines

**Current**: Sine wave horizontal displacement with RGB split

**Goal**: Add VHS-style tracking, block-compression artifacts, and datamoshing-style motion smearing.

**Core Building Blocks**

| Function | Purpose |
|----------|---------|
| `sawtoothWave(x)` | Classic TV-line "ramp" used for horizontal jitter. |
| `fbm(p, octaves)` | Organic displacement for "datamosh". |
| `blockCorruption(uv, blockId, intensity, time)` | Quantises UV to a macro-block grid and adds a random offset. |
| `vhsTracking(uv, time, intensity)` | Horizontal sync jitter + vertical roll. |
| `estimateLumaGradient(uv)` | Edge detection for smear direction. |

**Implementation Sketch (≈ 120 lines)**

```wgsl
// ── BASIC Waveforms ─────────────────────────────────────
fn sawtoothWave(x: f32) -> f32 {
    return fract(x);
}

// ── VHS Tracking (horizontal sync jitter) ─────────────────
fn vhsTracking(uv: vec2<f32>, time: f32, intensity: f32) -> vec2<f32> {
    // jitter frequency ~ 15‑30 Hz (typical TV line rate)
    let jitter = sin(time * 30.0 + uv.y * 1000.0) * intensity * 0.001;
    // vertical roll (slow drift)
    let roll = sin(time * 0.2) * 0.001;
    return uv + vec2<f32>(jitter, roll);
}

// ── Block‑level corruption (macro‑blocking) ─────────────────
fn blockCorruption(uv: vec2<f32>, blockSize: f32,
                   intensity: f32, time: f32) -> vec2<f32> {
    // identify block id
    let blockId = floor(uv / blockSize);
    // generate a pseudo‑random offset per block
    let rnd = hash21(blockId + vec2<f32>(time, u.zoom_params.w)); // seed via param
    let offset = (rnd - 0.5) * intensity * blockSize;
    return uv + offset;
}

// ── Datamosh‑style displacement (fbm) ───────────────────────
fn datamoshDisp(uv: vec2<f32>, time: f32) -> vec2<f32> {
    let n = fbm(uv * 12.0 + time * 2.0, 3);
    // smear direction follows image gradient (approx)
    let grad = vec2<f32>(valueNoise(uv + vec2<f32>(0.001,0.0)) -
                        valueNoise(uv - vec2<f32>(0.001,0.0)),
                        valueNoise(uv + vec2<f32>(0.0,0.001)) -
                        valueNoise(uv - vec2<f32>(0.0,0.001)));
    return uv + normalize(grad) * n * u.zoom_params.z; // smearScale via param
}

// ── MAIN COMPUTE ─────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let uv = vec2<f32>(global_id.xy) / vec2<f32>(u.config.z, u.config.w);
    // 1️⃣ VHS tracking jitter
    var warped = vhsTracking(uv, u.config.x, u.zoom_params.x); // time, vhsJitter via params
    // 2️⃣ Block corruption (macro‑blocking)
    warped = blockCorruption(warped, 0.08, u.zoom_params.y, u.config.x); // intensity via param
    // 3️⃣ Datamosh displacement
    warped = datamoshDisp(warped, u.config.x);
    // 4️⃣ Sample the source texture
    let col = textureSampleLevel(readTexture, u_sampler, clamp(warped, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    // 5️⃣ Optional “glitch flicker” – modulate brightness with sawtooth
    let flicker = 0.8 + 0.2 * sawtoothWave(u.config.x * 12.0);
    textureStore(writeTexture, global_id.xy, vec4<f32>(col.rgb * flicker, col.a));
}
```

**Line count** – ~115 lines (plus the shared utilities). Add a few UI-binding lines and you’re at ≈140.

**Performance & Quality Tips**

| Tip | Detail |
|-----|--------|
| Clamp UV before sampling | After `blockCorruption` the UV can go out-of-bounds. Use `clamp(warped, vec2<f32>(0.0), vec2<f32>(1.0))`. |
| Reduce fbm octaves | 3 octaves are enough for a subtle "smear". |
| Temporal coherence | Store the previous frame’s texture in a bind-group and blend it (`mix(col, prevCol, 0.1)`) to get a "ghosting" datamosh feel without extra passes. |
| Uniform block size | Expose `blockSize` as a UI slider (0.02-0.15). Larger blocks give classic MPEG macro-blocking; smaller blocks give a "pixel-shatter" look. |

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

### 5. radial-rgb.wgsl (73 lines) → 135 lines

**Current**: Radial chromatic aberration with mouse distance falloff

**Goal**: Turn the simple chromatic-aberration into a full-lens model (barrel/pincushion, spectral dispersion, anamorphic streaks, vignette).

**New Functions**

| Function | Description |
|----------|-------------|
| `lensDistort(uv, center, coeffs)` | Implements `r * (1 + k₁r² + k₂r⁴ + k₃r⁶)` for barrel/pincushion. |
| `wavelengthToRGB(λ)` | Approximate CIE 1931 mapping (fast 3-point piecewise). |
| `sampleSpectral(uv, dispersion, direction)` | Samples the source texture at several wavelengths and blends. |
| `applyVignette(color, uv, intensity, roundness)` | Darkens corners, optional elliptical shape. |

**Full Shader (≈ 120 lines)**

```wgsl
// ── LENS DISTORTION (radial) ─────────────────────────────────
fn lensDistort(uv: vec2<f32>, center: vec2<f32>, coeffs: vec3<f32>) -> vec2<f32> {
    let d = uv - center;
    let r2 = dot(d, d);
    let factor = 1.0 + coeffs.x * r2 + coeffs.y * r2 * r2 + coeffs.z * r2 * r2 * r2;
    return center + d * factor;
}

// ── WAVELENGTH → RGB (fast approximation) ───────────────────
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    // 380‑780 nm, three linear ramps
    if (lambda < 440.0) {
        return vec3<f32>(-(lambda - 440.0) / 60.0, 0.0, 1.0);
    } else if (lambda < 490.0) {
        return vec3<f32>(0.0, (lambda - 440.0) / 50.0, 1.0);
    } else if (lambda < 510.0) {
        return vec3<f32>(0.0, 1.0, -(lambda - 510.0) / 20.0);
    } else if (lambda < 580.0) {
        return vec3<f32>((lambda - 510.0) / 70.0, 1.0, 0.0);
    } else if (lambda < 645.0) {
        return vec3<f32>(1.0, -(lambda - 645.0) / 65.0, 0.0);
    } else {
        return vec3<f32>(1.0, 0.0, 0.0);
    }
}

// ── SPECTRAL SAMPLING (dispersion + anamorphic) ───────────────
fn sampleSpectral(uv: vec2<f32>, dispersion: f32,
                  direction: vec2<f32>) -> vec3<f32> {
    // sample 7 wavelengths (red → violet)
    var col = vec3<f32>(0.0);
    let baseLambda = 650.0; // start at red
    let step = dispersion / 6.0;
    for (var i = 0; i < 7; i = i + 1) {
        let l = baseLambda - f32(i) * step;
        // shift UV along dispersion direction (scaled by wavelength)
        let shift = direction * (l - 550.0) * 0.00002; // arbitrary scale
        let sample = textureSampleLevel(readTexture, u_sampler, uv + shift, 0.0).rgb;
        col = col + sample * wavelengthToRGB(l);
    }
    return col / 7.0; // average
}

// ── VIGNETTE (optional elliptical) ───────────────────────────
fn applyVignette(color: vec3<f32>, uv: vec2<f32>,
                intensity: f32, roundness: f32) -> vec3<f32> {
    let centered = uv - vec2<f32>(0.5);
    let d = length(centered * vec2<f32>(roundness, 1.0));
    let vign = smoothstep(0.5, 0.5 - intensity, d);
    return color * vign;
}

// ── ENTRY POINT ───────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let uv = vec2<f32>(global_id.xy) / vec2<f32>(u.config.z, u.config.w);
    // 1️⃣ Lens distortion (barrel/pincushion)
    let distorted = lensDistort(uv, vec2<f32>(0.5), vec3<f32>(u.zoom_params.x, u.zoom_params.y, 0.0)); // k1, k2 via params
    // 2️⃣ Depth‑aware CoC (optional, keep for future)
    // let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, distorted, 0.0).r;
    // let coc = calculateCoC(depth, focalDepth, maxBlur);
    // 3️⃣ Spectral dispersion (direction = mouse → centre)
    let mouse = u.zoom_config.yz;
    let dir = normalize(mouse - vec2<f32>(0.5));
    // Anamorphic stretch: scale X component
    let dispDir = dir * vec2<f32>(u.zoom_params.z, 1.0); // anamorphic via param
    let col = sampleSpectral(distorted, u.zoom_params.w, dispDir); // dispersion via param
    // 4️⃣ Vignette
    let final = applyVignette(col, uv, 0.3, 1.0);
    textureStore(writeTexture, global_id.xy, vec4<f32>(final, 1.0));
}
```

**Line count** – ~115 lines (plus the shared utilities). Add a few UI-binding lines and you’re at ≈135.

**Visual Tuning Guide**

| UI Slider | Effect |
|-----------|--------|
| k1 / k2 | Negative → barrel, positive → pincushion. |
| dispersion | Larger → stronger spectral "rainbow fringe". |
| anamorphic | >1 stretches horizontally (film-like streaks). |
| vignetteStr / vignetteRound | Controls darkness and shape of the edge fade. |
| time (or mouse) | Drives the direction of the dispersion vector. |

**Performance**
- Spectral sampling does 7 texture reads per pixel. If you need > 60 fps on mobile, reduce to 3-5 samples or pre-bake a lookup texture that encodes the dispersion for a given direction.
- The lens distortion is a cheap single arithmetic op; it can be moved to a vertex shader if you render a full-screen quad (the UVs are already distorted).

**RGBA Enhancement**:
- R: Spectral red (650nm)
- G: Spectral green (550nm)
- B: Spectral blue (450nm)
- A: Lens transmission factor

---

### 6. synthwave-grid-warp.wgsl (74 lines) → 145 lines

**Current**: 2D synthwave grid with mouse warp

**Goal**: Turn the flat 2-D grid into a perspective-projected 3-D floor with atmospheric fog, a sun, and a distant mountain silhouette.

**High-Level Pipeline**

1. **Screen → World**: `screenToWorld` maps UV to a 3-D point on a plane at y = 0.
2. **Perspective Projection**: Apply a simple focal length (fov) to get depth.
3. **Grid Rendering**: Use an SDF `sdGrid` (repeating lines) on the X-Z plane.
4. **Atmospheric Fog**: `heightFog` attenuates based on distance and height.
5. **Sun + Lens Flare**: `renderSun` draws a bright disc with a spike bloom.
6. **Mountains**: `mountainLayer` uses a 1-D noise height map and SDF for silhouettes.

**Full Shader (≈ 130 lines)**

```wgsl
// ── SCREEN → WORLD (simple perspective) ─────────────────────
fn screenToWorld(uv: vec2<f32>, camY: f32, fov: f32) -> vec3<f32> {
    // map uv (0‑1) → NDC (‑1‑1)
    let ndc = (uv - vec2<f32>(0.5)) * 2.0;
    // perspective division
    let z = 1.0 / tan(fov * 0.5);
    let x = ndc.x * z;
    let y = ndc.y * z + camY;
    return vec3<f32>(x, -camY, y); // Y‑up world (ground at y=0)
}

// ── GRID SDF (repeating lines) ─────────────────────────────────
fn sdGrid(p: vec3<f32>, spacing: f32) -> f32 {
    // distance to nearest X‑Z line
    let gx = abs(fract(p.x / spacing - 0.5) - 0.5);
    let gz = abs(fract(p.z / spacing - 0.5) - 0.5);
    return min(gx, gz) * spacing;
}

// ── HEIGHT‑FOG (exponential) ─────────────────────────────────
fn heightFog(dist: f32, height: f32, density: f32, falloff: f32) -> f32 {
    // exponential attenuation with height
    return exp(-density * dist) * exp(-falloff * max(0.0, height));
}

// ── SUN + FLARE ───────────────────────────────────────────────
fn renderSun(uv: vec2<f32>, sunPos: vec2<f32>, size: f32, glow: f32) -> vec3<f32> {
    let d = length(uv - sunPos);
    // core disc
    let core = smoothstep(size, size - 0.001, d);
    // glow halo
    let halo = pow(smoothstep(size + glow, size, d), 2.0);
    return vec3<f32>(1.0, 0.9, 0.6) * (core + halo * 0.5);
}

// ── MOUNTAIN LAYER (1‑D noise height map) ─────────────────────
fn mountainLayer(uv: vec2<f32>, layerZ: f32, scale: f32,
                 height: f32, sunPos: vec2<f32>) -> vec4<f32> {
    // sample noise along X axis, repeat every 1.0
    let n = textureSampleLevel(readTexture, u_sampler,
                               vec2<f32>(uv.x * scale, 0.0), 0.0).r;
    let h = n * height;
    // SDF for silhouette (simple step)
    let dist = uv.y - h;
    let inside = step(dist, 0.0);
    // color shading (dusk palette)
    let col = mix(vec3<f32>(0.1, 0.07, 0.2),
                  vec3<f32>(0.3, 0.2, 0.4), inside);
    // optional rim lighting from sun direction
    let rim = max(dot(normalize(vec2<f32>(0.0, 1.0) - vec2<f32>(0.0, h)), normalize(sunPos - uv)), 0.0);
    let col2 = col + rim * 0.2;
    return vec4<f32>(col2, inside);
}

// ── MAIN COMPUTE ─────────────────────────────────────────────
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let uv = vec2<f32>(global_id.xy) / vec2<f32>(u.config.z, u.config.w);
    // 1️⃣ world position on ground plane
    let worldPos = screenToWorld(uv, u.zoom_params.x, 1.2); // camY via param
    // 2️⃣ distance from camera (for fog)
    let dist = length(worldPos);
    // 3️⃣ grid line distance
    let gridDist = sdGrid(worldPos, 0.5);
    // 4️⃣ base grid color (neon cyan)
    let gridCol = vec3<f32>(0.0, 0.8, 1.0) * smoothstep(0.02, 0.0, gridDist);
    // 5️⃣ fog factor
    let fog = heightFog(dist, worldPos.y, u.zoom_params.y, u.zoom_params.z); // density, falloff via params
    // 6️⃣ sun
    let sun = renderSun(uv, vec2<f32>(0.5, 0.3), 0.05, 0.2);
    // 7️⃣ mountains (two layers for parallax)
    let m1 = mountainLayer(uv, 0.2, u.zoom_params.w, 0.15, vec2<f32>(0.5, 0.3)); // mountainScale via param
    let m2 = mountainLayer(uv, 0.5, u.zoom_params.w * 1.5, 0.09, vec2<f32>(0.5, 0.3));
    // 8️⃣ composite
    var col = gridCol * (1.0 - fog) + sun * fog;
    col = mix(col, m1.rgb, m1.a);
    col = mix(col, m2.rgb, m2.a);
    // 9️⃣ final tone‑mapping (simple Reinhard)
    col = col / (col + vec3<f32>(1.0));
    textureStore(writeTexture, global_id.xy, vec4<f32>(col, 1.0));
}
```

**Line count** – ~130 lines (including the shared utilities). Add a few UI-binding lines and you land at ≈145.

**Tuning Tips**

| Parameter | Visual Effect |
|-----------|---------------|
| camY | Higher → more "fly-over" feeling, longer view distance. |
| fov | Wide (≈ 1.2 rad) gives classic synth-wave perspective; narrow → more "cinematic". |
| fogDensity / fogFalloff | Controls haze thickness and how quickly it fades with height. |
| sunSize / sunGlow | Larger → softer halo, smaller → crisp disc. |
| mountainScale / mountainHeight | Controls frequency and amplitude of the silhouette. |
| time (optional) | Animate camY or sunPos for a moving sunrise. |

**Performance**
- Two mountain layers = 2 texture reads (noise). Keep the noise texture 128 × 128 or lower for mobile.
- Grid SDF is a single min/abs operation – essentially free.
- If you need extra speed, pre-compute the grid into a lookup texture and just sample it.

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
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}
fn hash11(p: f32) -> f32 {
    return fract(sin(p * 12.9898) * 43758.5453);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i = i + 1) {
        sum = sum + amp * valueNoise(p * freq);
        freq = freq * 2.0;
        amp = amp * 0.5;
    }
    return sum;
}

// ═══ COLOR UTILITIES ═══
fn rgbToLuma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}
fn rgbToYuv(rgb: vec3<f32>) -> vec3<f32> {
    let y = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b;
    let u = -0.14713 * rgb.r - 0.28886 * rgb.g + 0.436 * rgb.b;
    let v = 0.615 * rgb.r - 0.51499 * rgb.g - 0.10001 * rgb.b;
    return vec3<f32>(y, u, v);
}
fn yuvToRgb(yuv: vec3<f32>) -> vec3<f32> {
    let r = yuv.x + 1.13983 * yuv.z;
    let g = yuv.x - 0.39465 * yuv.y - 0.58060 * yuv.z;
    let b = yuv.x + 2.03211 * yuv.y;
    return vec3<f32>(r, g, b);
}
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let c = hsv.z * hsv.y;
    let h = hsv.x * 6.0;
    let x = c * (1.0 - abs(fract(h) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else              { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(hsv.z - c);
}

// ═══ SDF PRIMITIVES ═══
fn sdCircle(p: vec2<f32>, r: f32) -> f32 {
    return length(p) - r;
}
fn sdBox(p: vec2<f32>, b: vec2<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec2<f32>(0.0))) + min(max(d.x, d.y), 0.0);
}
fn sdLine(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}
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

---

## Quick-Start Checklist for All Shaders

| Step | What to do | Why |
|------|------------|-----|
| 1️⃣ | Create a uniform buffer | Include all UI-exposed parameters (time, strength, etc.). | Allows live tweaking from JavaScript/Unity/Unreal. |
| 2️⃣ | Bind textures | Color, depth, optional noise. | Keeps the shader pure – no hard-coded URLs. |
| 3️⃣ | Insert the shared utilities | Copy the 30-line block at the top. | Re-use hash, noise, color conversion, SDF. |
| 4️⃣ | Add a `@compute @workgroup_size(16,16,1)` entry | Follow the pattern shown. | Guarantees a consistent entry point. |
| 5️⃣ | Compile & test | Render a full-screen quad, compare before/after. | Spot any UV-clamping or performance spikes early. |
| 6️⃣ | Profile | Use WebGPU/Metal/DirectX debug tools. | Ensure 60 fps on target hardware. |
