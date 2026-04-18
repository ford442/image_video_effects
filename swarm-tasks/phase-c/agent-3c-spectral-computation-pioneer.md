# Agent 3C: Spectral Computation Pioneer
## Task Specification — Phase C, Agent 3

**Role:** Novel WGSL Computation Methods & Spectral Rendering Specialist  
**Priority:** HIGH  
**Target:** 15 shaders using computation techniques not yet in the library  
**Estimated Duration:** 5-7 days

---

## Mission

Introduce **computation methods that no existing shader in the library uses**. The current library has basic shared memory tiles, standard noise functions, finite-difference normals, and bilinear sampling. This agent pushes into:

1. **Spectral / multi-wavelength rendering** (treating RGBA as 4 spectral bands)
2. **Stochastic / Monte Carlo methods** (blue-noise, importance sampling, temporal accumulation)
3. **Cooperative workgroup patterns** (prefix sums, reductions, histogram equalization)
4. **Quaternion and higher-dimensional math** (4D rotations, hypercube projections)
5. **Bicubic and higher-order sampling** (Catmull-Rom, B-spline interpolation)
6. **Analytic derivatives** (eliminating finite-difference normal calculation overhead)

Each shader must produce **visually stunning results** that are obviously different from anything in the current library — the computation technique should create effects that are literally impossible without it.

---

## Technique Catalog

### Tier 1: Spectral Rendering (Wavelength-Based Color)

#### 1. `spec-prismatic-dispersion.wgsl` — 4-Band Spectral Dispersion Through Glass
**Technique:** Render the scene as 4 separate wavelength bands (450nm violet, 520nm green, 600nm orange, 680nm red). Each band refracts through a glass surface at a slightly different angle (chromatic dispersion via Cauchy's equation). Final color is reconstructed from the 4 bands using CIE color matching.

**Why it's new:** Current shaders separate R/G/B channels but treat them as display primaries. This shader treats RGBA as physical wavelengths with measurable optical properties. The dispersion is physically correct, not just "shift red left, blue right."

**Implementation:**
```wgsl
// Cauchy's equation for refractive index
fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
    let lambdaUm = wavelengthNm * 0.001; // Convert nm to μm
    return A + B / (lambdaUm * lambdaUm);
}

// 4 wavelength bands
const WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);

// CIE 1931 color matching (simplified)
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    // Approximate CIE XYZ → sRGB for given wavelength
    let t = (lambda - 440.0) / (680.0 - 440.0);
    let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
    let g = 1.0 - abs(t - 0.4) * 3.0;
    let b = 1.0 - smoothstep(0.0, 0.4, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    // ... setup ...
    
    // Refract each wavelength separately
    var finalColor = vec3<f32>(0.0);
    var spectralResponse = vec4<f32>(0.0);
    
    for (var i = 0; i < 4; i++) {
        let ior = cauchyIOR(WAVELENGTHS[i], 1.5, 0.01);
        let refractedUV = refractThroughSurface(uv, mousePos, ior);
        let sample = textureSampleLevel(readTexture, u_sampler, refractedUV, 0.0);
        let bandIntensity = dot(sample.rgb, wavelengthToRGB(WAVELENGTHS[i]));
        spectralResponse[i] = bandIntensity;
        finalColor += wavelengthToRGB(WAVELENGTHS[i]) * bandIntensity;
    }
    
    // RGBA stores 4 spectral bands for downstream use
    textureStore(writeTexture, gid.xy, vec4<f32>(finalColor, spectralResponse.w));
    textureStore(dataTextureA, gid.xy, spectralResponse); // Full 4-band data
}
```

**Params:**
| Param | Name | Default | Range | Purpose |
|-------|------|---------|-------|---------|
| x | Glass Curvature | 0.5 | 0.0-1.0 | Surface curvature |
| y | Cauchy B (Dispersion) | 0.3 | 0.0-1.0 | How much dispersion |
| z | Glass Thickness | 0.5 | 0.0-1.0 | Absorption path length |
| w | Spectral Saturation | 0.7 | 0.0-1.0 | Color intensity |

---

#### 2. `spec-iridescence-engine.wgsl` — Thin-Film Interference (Soap Bubbles / Oil Slicks)
**Technique:** Simulates thin-film interference where the reflected color depends on viewing angle and film thickness. Uses the depth texture to define "film thickness" at each pixel. Creates iridescent, oil-slick rainbow effects that shift with perspective.

**Physics:**
```wgsl
fn thinFilmColor(thickness: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
    // Optical path difference = 2 * n * d * cos(theta_t)
    // where theta_t = refracted angle inside film
    let sinTheta_t = sqrt(1.0 - cosTheta * cosTheta) / filmIOR;
    let cosTheta_t = sqrt(1.0 - sinTheta_t * sinTheta_t);
    let opd = 2.0 * filmIOR * thickness * cosTheta_t;
    
    // Interference: each wavelength interferes constructively/destructively
    var color = vec3<f32>(0.0);
    for (var lambda = 380.0; lambda <= 700.0; lambda += 20.0) {
        let phase = opd / (lambda * 0.001); // Convert nm to μm
        let interference = cos(phase * 6.2832) * 0.5 + 0.5;
        color += wavelengthToRGB(lambda) * interference;
    }
    return color / 16.0; // Normalize by sample count
}
```

**RGBA32FLOAT exploitation:**
- RGB: Iridescent reflected color (HDR — constructive interference can create values > 1.0)
- A: Film thickness at this pixel (continuous f32 — enables smooth thickness gradients)

---

#### 3. `spec-blackbody-thermal.wgsl` — Blackbody Radiation Coloring
**Technique:** Maps image luminance to physically-correct blackbody radiation colors (Planck's law). Dark regions glow like cooling embers (1000K red), medium brightness = white heat (6500K), and bright regions = blue-hot plasma (15000K+).

```wgsl
fn blackbodyColor(temperatureK: f32) -> vec3<f32> {
    // Planck's law approximation via fitted polynomial
    let t = temperatureK / 1000.0;
    let t2 = t * t;
    
    var r: f32; var g: f32; var b: f32;
    
    if (t <= 6.5) {
        r = 1.0;
        g = clamp(0.39 * log(t) - 0.63, 0.0, 1.0);
        b = clamp(0.54 * log(t - 1.0) - 1.0, 0.0, 1.0);
    } else {
        r = clamp(1.29 * pow(t - 0.6, -0.13), 0.0, 1.0);
        g = clamp(1.29 * pow(t - 0.6, -0.076), 0.0, 1.0);
        b = 1.0;
    }
    
    // Scale by Stefan-Boltzmann: total radiance ∝ T⁴
    let radiance = pow(t / 6.5, 4.0);
    return vec3<f32>(r, g, b) * radiance;
}
```

**RGBA32FLOAT exploitation:** Radiance values at 15000K can reach 30.0+ before tone mapping. Without f32, the dynamic range of thermal rendering is catastrophically compressed.

---

### Tier 2: Stochastic & Monte Carlo Methods

#### 4. `spec-temporal-path-tracer.wgsl` — 2D Path Tracer with Temporal Accumulation
**Technique:** Cast light rays from each pixel that bounce off "surfaces" defined by image edges/depth. Uses `dataTextureC` to accumulate samples over time (Monte Carlo integration). After 60 frames, the image shows soft global illumination with caustics and color bleeding.

**Implementation:**
```wgsl
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let prev = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);
    let sampleCount = prev.a;
    
    // Generate ray direction with blue-noise jitter
    let blueNoise = hash22(vec2<f32>(gid.xy) + vec2<f32>(sampleCount * 1.618));
    let rayDir = normalize(blueNoise - 0.5);
    
    // Trace: march along ray, bounce off edges
    var pos = vec2<f32>(gid.xy) / u.config.zw;
    var radiance = vec3<f32>(0.0);
    var throughput = vec3<f32>(1.0);
    
    for (var bounce = 0; bounce < 4; bounce++) {
        // March until hitting an edge (high gradient)
        let hitResult = marchToEdge(pos, rayDir, 64);
        if (!hitResult.hit) { break; }
        
        // Sample color at hit point
        let hitColor = textureSampleLevel(readTexture, u_sampler, hitResult.pos, 0.0).rgb;
        radiance += throughput * hitColor * 0.5;
        throughput *= hitColor; // Color bleeding
        
        // Russian roulette termination
        let rrProb = max(throughput.r, max(throughput.g, throughput.b));
        if (hash11(sampleCount + f32(bounce)) > rrProb) { break; }
        throughput /= rrProb;
        
        // Bounce: reflect off surface normal
        pos = hitResult.pos;
        rayDir = reflect(rayDir, hitResult.normal);
    }
    
    // Temporal accumulation (running average)
    let newAccum = (prev.rgb * sampleCount + radiance) / (sampleCount + 1.0);
    textureStore(dataTextureA, gid.xy, vec4<f32>(newAccum, sampleCount + 1.0));
    
    // Tone-map for display
    let display = toneMapACES(newAccum);
    textureStore(writeTexture, gid.xy, vec4<f32>(display, 1.0));
}
```

**RGBA32FLOAT exploitation:** Alpha stores sample count (goes to 1000+ over time). RGB stores accumulated HDR radiance that can reach 50.0+ before normalization. Both require f32 precision.

---

#### 5. `spec-blue-noise-stipple.wgsl` — Blue-Noise Dithered Pointillism
**Technique:** Uses a blue-noise distribution (generated in-shader via Mitchell's best-candidate algorithm) to create a Seurat-style pointillist rendering. Each "dot" samples the local color and its size is determined by local luminance.

**Why it's new:** Existing stipple/halftone shaders use regular grids or white noise. Blue noise produces perceptually optimal, uniformly-spaced yet non-regular dot distributions. The difference is immediately visible — smoother gradients, no aliasing.

```wgsl
// Blue-noise approximation via golden ratio low-discrepancy sequence
fn blueNoiseOffset(pixelCoord: vec2<f32>, frame: f32) -> vec2<f32> {
    let phi2 = vec2<f32>(1.3247179572, 1.7548776662); // Plastic constant
    return fract(pixelCoord * phi2 + frame * phi2);
}
```

---

#### 6. `spec-importance-sampled-bokeh.wgsl` — Importance-Sampled Bokeh Blur
**Technique:** Bokeh blur where sample distribution is guided by image brightness (importance sampling). Bright pixels act as point light sources that create bokeh shapes. Instead of uniform disk sampling, samples are concentrated on bright areas — creating crisp bokeh highlights with smooth backgrounds.

```wgsl
fn importanceSampledBokeh(uv: vec2<f32>, radius: f32, shape: f32) -> vec4<f32> {
    var accumColor = vec3<f32>(0.0);
    var accumWeight = 0.0;
    
    for (var i = 0; i < 64; i++) {
        // Golden angle spiral sampling
        let angle = f32(i) * 2.39996; // Golden angle
        let r = sqrt(f32(i) / 64.0) * radius;
        let offset = vec2<f32>(cos(angle), sin(angle)) * r;
        
        let sampleUV = uv + offset / u.config.zw;
        let sample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
        let luma = dot(sample.rgb, vec3<f32>(0.299, 0.587, 0.114));
        
        // Importance weight: bright pixels contribute more (creates bokeh highlights)
        let importance = pow(luma, shape); // shape controls how "peaky" bokeh is
        
        accumColor += sample.rgb * importance;
        accumWeight += importance;
    }
    
    let result = accumColor / max(accumWeight, 0.001);
    return vec4<f32>(result, accumWeight / 64.0); // Alpha = average importance
}
```

---

### Tier 3: Cooperative Workgroup Patterns

#### 7. `spec-histogram-equalize.wgsl` — Real-Time Histogram Equalization via Workgroup Reduction
**Technique:** Computes a local histogram within each 8×8 workgroup tile, then uses the CDF to remap pixel intensities. Creates dramatic contrast enhancement that adapts to local image content (CLAHE — Contrast Limited Adaptive Histogram Equalization).

**Uses workgroup shared memory for cooperative histogram building:**
```wgsl
var<workgroup> localHistogram: array<atomic<u32>, 256>;

@compute @workgroup_size(8, 8, 1)
fn main(
    @builtin(global_invocation_id) gid: vec3<u32>,
    @builtin(local_invocation_id) lid: vec3<u32>,
    @builtin(local_invocation_index) lidx: u32
) {
    // Phase 1: Clear histogram (first 4 threads clear 64 bins each)
    for (var i = lidx; i < 256u; i += 64u) {
        atomicStore(&localHistogram[i], 0u);
    }
    workgroupBarrier();
    
    // Phase 2: Vote into histogram
    let luma = u32(dot(color.rgb, vec3(0.299, 0.587, 0.114)) * 255.0);
    let bin = clamp(luma, 0u, 255u);
    atomicAdd(&localHistogram[bin], 1u);
    workgroupBarrier();
    
    // Phase 3: Prefix sum (CDF) — use cooperative scan
    // Each thread computes CDF for its range
    var cdf = 0u;
    for (var i = 0u; i <= bin; i++) {
        cdf += atomicLoad(&localHistogram[i]);
    }
    
    // Phase 4: Remap
    let totalPixels = 64u; // 8×8 workgroup
    let equalizedLuma = f32(cdf) / f32(totalPixels);
    let scaleFactor = equalizedLuma / max(dot(color.rgb, vec3(0.299, 0.587, 0.114)), 0.001);
    let equalized = color.rgb * scaleFactor;
    
    textureStore(writeTexture, gid.xy, vec4<f32>(equalized, f32(cdf) / f32(totalPixels)));
}
```

**RGBA32FLOAT exploitation:** Alpha stores the CDF value (position in the local histogram). This is a continuous float that downstream shaders can use as a "statistical importance" map — pixels with unusual colors (low CDF position) get highlighted differently from common colors.

---

#### 8. `spec-cooperative-edge-linking.wgsl` — Workgroup-Cooperative Edge Linking
**Technique:** Beyond simple edge detection — after detecting edges, use workgroup shared memory to trace edge chains across the tile. Connected edges are assigned the same "edge ID" (stored in alpha), enabling downstream effects like edge-only coloring, edge flow animation, or edge-based segmentation.

---

### Tier 4: Higher-Dimensional Mathematics

#### 9. `spec-quaternion-julia.wgsl` — 4D Quaternion Julia Set Raymarched
**Technique:** Raymarch a 4D quaternion Julia set, projected into 3D and then to screen. The 4th dimension is animated over time, creating an organic morphing fractal that appears to breathe and evolve.

```wgsl
fn quaternionMul(a: vec4<f32>, b: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(
        a.x*b.x - a.y*b.y - a.z*b.z - a.w*b.w,
        a.x*b.y + a.y*b.x + a.z*b.w - a.w*b.z,
        a.x*b.z - a.y*b.w + a.z*b.x + a.w*b.y,
        a.x*b.w + a.y*b.z - a.z*b.y + a.w*b.x
    );
}

fn quaternionJuliaDE(p: vec3<f32>, c: vec4<f32>) -> f32 {
    var q = vec4<f32>(p, 0.0);
    var dq = vec4<f32>(1.0, 0.0, 0.0, 0.0);
    
    for (var i = 0; i < 12; i++) {
        // dq = 2 * q * dq (chain rule for derivative)
        dq = 2.0 * quaternionMul(q, dq);
        // q = q² + c
        q = quaternionMul(q, q) + c;
        
        if (dot(q, q) > 256.0) { break; }
    }
    
    let r = length(q);
    let dr = length(dq);
    return 0.5 * r * log(r) / dr;
}
```

**RGBA32FLOAT exploitation:** Alpha stores the orbit trap distance (how close the iteration came to a reference shape). This continuous f32 value enables smooth, detailed coloring of the fractal interior.

---

#### 10. `spec-hypercube-projection.wgsl` — Animated 4D Hypercube (Tesseract) Projection
**Technique:** Renders a 4D tesseract projected into 2D using a double rotation (one in the XW plane, one in YZ). The 4D vertices are connected by edges that occlude each other based on their 4D depth. The input image is texture-mapped onto the tesseract faces.

**4D rotation using two rotation matrices:**
```wgsl
fn rotate4D_XW(p: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle); let s = sin(angle);
    return vec4<f32>(c*p.x + s*p.w, p.y, p.z, -s*p.x + c*p.w);
}

fn rotate4D_YZ(p: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle); let s = sin(angle);
    return vec4<f32>(p.x, c*p.y + s*p.z, -s*p.y + c*p.z, p.w);
}
```

---

#### 11. `spec-spherical-harmonics-light.wgsl` — Spherical Harmonics Lighting
**Technique:** Uses spherical harmonic coefficients to represent the lighting environment from the input image. Applies the SH lighting to a normal-mapped surface (normals derived from depth). Creates realistic ambient lighting that responds to image content.

```wgsl
// SH band 0-2 evaluation
fn evaluateSH(normal: vec3<f32>, coeffs: array<vec3<f32>, 9>) -> vec3<f32> {
    // Band 0
    var result = coeffs[0] * 0.282095;
    // Band 1
    result += coeffs[1] * 0.488603 * normal.y;
    result += coeffs[2] * 0.488603 * normal.z;
    result += coeffs[3] * 0.488603 * normal.x;
    // Band 2
    result += coeffs[4] * 1.092548 * normal.x * normal.y;
    result += coeffs[5] * 1.092548 * normal.y * normal.z;
    result += coeffs[6] * 0.315392 * (3.0 * normal.z * normal.z - 1.0);
    result += coeffs[7] * 1.092548 * normal.x * normal.z;
    result += coeffs[8] * 0.546274 * (normal.x * normal.x - normal.y * normal.y);
    return result;
}
```

---

### Tier 5: Advanced Sampling & Interpolation

#### 12. `spec-bicubic-crystal.wgsl` — Bicubic Catmull-Rom Crystalline Distortion
**Technique:** Implements full bicubic Catmull-Rom interpolation for silky-smooth UV distortion. Where bilinear interpolation creates visible staircasing in magnified regions, bicubic produces perfectly smooth curves. Applied to a crystalline faceting distortion.

```wgsl
fn catmullRom(t: f32) -> vec4<f32> {
    let t2 = t * t;
    let t3 = t2 * t;
    return vec4<f32>(
        -0.5*t3 + t2 - 0.5*t,           // w0
        1.5*t3 - 2.5*t2 + 1.0,           // w1
        -1.5*t3 + 2.0*t2 + 0.5*t,        // w2
        0.5*t3 - 0.5*t2                    // w3
    );
}

fn sampleBicubic(tex: texture_2d<f32>, samp: sampler, uv: vec2<f32>, texSize: vec2<f32>) -> vec4<f32> {
    let pixel = uv * texSize - 0.5;
    let frac = fract(pixel);
    let base = floor(pixel);
    
    let wx = catmullRom(frac.x);
    let wy = catmullRom(frac.y);
    
    var result = vec4<f32>(0.0);
    for (var j = -1; j <= 2; j++) {
        for (var i = -1; i <= 2; i++) {
            let coord = (base + vec2<f32>(f32(i), f32(j)) + 0.5) / texSize;
            let sample = textureSampleLevel(tex, samp, coord, 0.0);
            result += sample * wx[i + 1] * wy[j + 1];
        }
    }
    return result;
}
```

---

#### 13. `spec-analytic-noise-flow.wgsl` — Noise with Analytic Derivatives for Flow Fields
**Technique:** Implements Perlin noise with **analytic derivatives** — the gradient is computed alongside the noise value in a single evaluation (no extra evaluations needed). Used to create perfectly smooth flow fields without the jitter of finite-difference gradients.

```wgsl
fn noiseWithDerivative(p: vec2<f32>) -> vec3<f32> {
    // Returns: x = noise value, yz = analytic gradient (∂n/∂x, ∂n/∂y)
    let i = floor(p);
    let f = fract(p);
    
    // Quintic interpolation with analytic derivative
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
    
    // Hash corners
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    
    // Value
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

**Visual result:** Ultra-smooth flow fields that create perfectly parallel streamlines without the wobble caused by numerical differentiation.

---

#### 14. `spec-runge-kutta-advection.wgsl` — 4th-Order Runge-Kutta Flow Advection
**Technique:** Standard fluid advection uses Euler's method (pos -= vel * dt) which is inaccurate and causes dissipation. RK4 advection is dramatically more accurate — fluid structures maintain their shape 10x longer.

```wgsl
fn advectRK4(pos: vec2<f32>, dt: f32) -> vec2<f32> {
    let k1 = sampleVelocity(pos);
    let k2 = sampleVelocity(pos + k1 * dt * 0.5);
    let k3 = sampleVelocity(pos + k2 * dt * 0.5);
    let k4 = sampleVelocity(pos + k3 * dt);
    return pos + (k1 + 2.0*k2 + 2.0*k3 + k4) * dt / 6.0;
}
```

**Applied to:** A dye-in-fluid simulation where the input image is the dye. Mouse creates vortex pairs. The RK4 advection preserves fine detail that Euler method would smear away within seconds.

---

#### 15. `spec-distance-field-text.wgsl` — SDF-Based Procedural Text/Glyph Overlay
**Technique:** Generates text or symbolic glyphs as Signed Distance Fields directly in the shader. The SDF approach enables infinitely smooth scaling, glowing edges, drop shadows, and outline effects — all from a single distance value per pixel.

```wgsl
fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

fn sdDigit(p: vec2<f32>, digit: i32) -> f32 {
    // 7-segment display SDF
    var d = 999.0;
    // Segments: top, top-right, bottom-right, bottom, bottom-left, top-left, middle
    let segments = array<u32, 10>(0x7Eu, 0x30u, 0x6Du, 0x79u, 0x33u, 0x5Bu, 0x5Fu, 0x70u, 0x7Fu, 0x7Bu);
    let mask = segments[digit];
    
    if ((mask & 0x40u) != 0u) { d = min(d, sdSegment(p, vec2(-0.3, 0.5), vec2(0.3, 0.5))); }
    // ... more segments
    
    return d;
}
```

**Visual output:** Overlay shader parameters, coordinates, or debug info as crisp, glow-edged text over the image. The SDF approach creates beautiful anti-aliased text that scales perfectly.

---

## Tone Mapping Functions (Shared Utility)

Every shader producing HDR output should include a tone mapper:

```wgsl
// ═══ CHUNK: toneMapACES (Agent 3C) ═══
fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

// ═══ CHUNK: toneMapFilmic (Agent 3C) ═══
fn toneMapFilmic(x: vec3<f32>) -> vec3<f32> {
    let a = max(vec3(0.0), x - 0.004);
    return (a * (6.2 * a + 0.5)) / (a * (6.2 * a + 1.7) + 0.06);
}
```

---

## Deliverables

1. **15 WGSL shader files** with novel computation techniques
2. **15 JSON definition files** with appropriate categories
3. **Each shader must:**
   - Use a computation technique NOT in the current library
   - Produce visually distinctive results (not achievable without the technique)
   - Include mouse responsiveness
   - Exploit RGBA32FLOAT precision meaningfully
4. **Utility code chunks** to add to `swarm-outputs/chunk-library.md`:
   - `toneMapACES`, `toneMapFilmic`
   - `sampleBicubic`, `catmullRom`
   - `noiseWithDerivative`
   - `quaternionMul`, `quaternionJuliaDE`
   - `wavelengthToRGB`, `cauchyIOR`
   - `advectRK4`

---

## Success Criteria

- [ ] All 15 shaders compile without WGSL errors
- [ ] Each shader uses a genuinely novel computation technique
- [ ] HDR shaders correctly tone-map before output to writeTexture
- [ ] Temporal shaders correctly read from dataTextureC and write to dataTextureA
- [ ] Performance: 30+ FPS (temporal shaders improve quality over time at 60fps)
- [ ] Visual quality demonstrably superior to simpler approaches
- [ ] JSON definitions include params, tags, description
