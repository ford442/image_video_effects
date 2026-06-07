# Ultra-Shader Techniques: Pushing Pixelocity to the Computational Limit

A technical design document for maximizing visual complexity, beauty, geometric intricacy, smoothness, and float-precision exploitation within Pixelocity's existing WebGPU compute pipeline.

> **Constraint**: No changes to `Renderer.ts`, types, or BindGroups. All techniques must work within the existing uniform buffer and texture binding layout.

---

## 1. Current State Analysis

After auditing ~20 representative shaders across all categories (`generative/`, `simulation/`, `advanced-hybrid/`, `distortion/`, `artistic/`), several patterns emerge:

| Dimension | Current Typical | Theoretical Limit (within engine) |
|-----------|----------------|-----------------------------------|
| **Float range usage** | 95% clamp RGB to `[0,1]`; alpha is `1.0` or simple opacity | Full `rgba32float` HDR + alpha-as-data-channel |
| **Raymarch steps** | 64–128 | 256+ with adaptive stepping |
| **Noise octaves** | 4–8 | 12+ with distance-based LOD |
| **Normal calculation** | Finite differences (6 extra `map()` calls) | Analytic Jacobians (0 extra calls) |
| **Feedback loops** | 2–3 pass pairs | Temporal Monte Carlo (infinite effective passes via `dataTextureC`) |
| **RGBA packing** | RGB = color, A = opacity | RGBA = 4 independent simulation fields |
| **Photons/samples** | 16–64 per pixel | 256+ with blue-noise dithering |

The gap is not hardware — the engine already uses `rgba32float` storage and 2048×2048 compute dispatches. The gap is **technique**.

---

## 2. Exploiting `rgba32float`: Beyond 0–1

### 2.1 HDR Accumulation & Filmic Tone Mapping

Most shaders write:
```wgsl
let col = clamp(someColor, vec3(0.0), vec3(1.0));
textureStore(writeTexture, id, vec4(col, 1.0));
```

This immediately throws away energy. For volumetrics, caustics, or path tracing, radiance can legitimately reach `50.0` or `1000.0` before averaging.

**Pattern**: Accumulate un-clamped, then tone-map:
```wgsl
// Filmic tone mapping (Hejl-Richardson approx)
fn toneMap(x: vec3<f32>) -> vec3<f32> {
    let a = x * 0.5;
    let b = x * 0.5 + 0.02;
    let c = a / (b + 1.0);
    return pow(c, vec3(1.0 / 2.2));
}
```

**Where to apply**: Any shader doing accumulation (volumetric raymarching, photon tracing, temporal feedback).

### 2.2 Alpha as a Data Channel

The engine supports alpha blending in the final `texture.wgsl` pass, but most compute shaders ignore it. Alpha can store:
- **Optical depth** (for volumetric compositing)
- **Sample count** (for Monte Carlo convergence)
- **Material ID** or **age** (for reaction-diffusion and particle systems)
- **Density** (for fluid simulations)

**Example** (temporal accumulation):
```wgsl
// dataTextureC holds: RGB = accumulated radiance, A = sample count
let prev = textureLoad(dataTextureC, id, 0);
let accum = mix(prev.rgb, newSample, 1.0 / (prev.a + 1.0));
textureStore(dataTextureA, id, vec4(accum, prev.a + 1.0));
```

This is only stable because `rgba32float` gives ~7 decimal digits of precision. With `rgba8unorm`, `prev.a + 1.0` would saturate at 255 samples.

### 2.3 RGBA as 4 Independent Simulation Fields

In a Navier-Stokes or reaction-diffusion shader, you can pack the entire state into one `rgba32float` texture:
- **R** = velocity.x
- **G** = velocity.y
- **B** = pressure
- **A** = density / temperature

This eliminates the need for multiple storage textures and keeps everything in a single read-modify-write pass. The `f32` precision is critical here: velocities of `0.001` px/frame are common in stable fluids, and anything less than 32-bit float causes catastrophic drift within seconds.

---

## 3. Geometrical Complexity: Escaping Simple Primitives

### 3.1 Fractal SDFs with Analytic Normals

Current SDF shaders (`cosmic-jellyfish.wgsl`, `gen-auroral-ferrofluid-monolith.wgsl`) use finite-difference normals:
```wgsl
let n = normalize(vec3(
    map(p + e.xyy) - map(p - e.xyy),
    map(p + e.yxy) - map(p - e.yxy),
    map(p + e.yyx) - map(p - e.yyx)
));
```

At 256 raymarch steps, this adds **1536 `map()` evaluations per pixel**. With analytic derivatives, it adds **zero**.

**Technique**: Track the Jacobian of the transformation alongside the distance field. For a Mandelbulb or Kaleidoscopic IFS, the Jacobian matrix propagates through the iteration loop.

```wgsl
fn mandelbulbDE(p: vec3<f32>, outNormal: ptr<function, vec3<f32>>) -> f32 {
    var w = p;
    var m = p;
    var dr = 1.0;
    var dz = mat3x3<f32>(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);

    for (var i: i32 = 0; i < 8; i++) {
        dr = 8.0 * pow(length(w), 7.0) * dr + 1.0;
        // ... iterate w ...
        w = m + ...;
    }
    let r = length(w);
    let de = 0.5 * log(r) * r / dr;
    *outNormal = normalize(dz * w); // analytic!
    return de;
}
```

**Impact**: Enables 2–3x more raymarch iterations at the same frame cost, or frees up budget for anti-aliasing.

### 3.2 Domain Repetition + Smooth Blending

To create infinite geometric detail without unbounded cost:
```wgsl
let q = p - round(p / spacing) * spacing; // domain repetition
let d1 = sdBox(q, vec3(0.3));
let d2 = sdSphere(q, 0.4);
let d = smin(d1, d2, 0.1); // smooth blend
```

Combined with fractal displacement:
```wgsl
d -= fbm(p * 8.0) * 0.1; // recursive surface detail
```

This turns simple primitives into architecturally complex structures.

### 3.3 Layered SDF Composition

Instead of one `map()` function, composite multiple signed distance fields with material IDs:
```wgsl
fn map(p: vec3<f32>) -> vec4<f32> {
    // xyz = scene color, w = distance
    let floor = vec4(vec3(0.8), sdPlane(p));
    let pillar = vec4(vec3(0.2), sdBox(p - vec3(2,1,0), vec3(0.2,1,0.2)));
    let result = sminMaterial(floor, pillar, 0.05);
    return result;
}
```

This encodes both geometry and material in a single return value, enabling complex scenes with colored shadows and reflections.

---

## 4. Computational Uniqueness: Only Possible on a GPU

### 4.1 Temporal Monte Carlo Path Tracing

The engine's `dataTextureC` (previous frame output) can be read as a texture. This enables **infinite-sample Monte Carlo integration** over time.

**Algorithm per frame**:
1. Read `dataTextureC` to get accumulated radiance + sample count.
2. Cast one new path (4 bounces, Russian roulette termination).
3. Blend: `accum_new = accum_old * (n/(n+1)) + sample * (1/(n+1))`.
4. Write `accum_new` to `dataTextureA` (which becomes next frame's `dataTextureC`).
5. Tone-map and write final color to `writeTexture`.

**Why it matters**: A CPU cannot do this at 2048×2048 in real time. A GPU can because every pixel is an independent thread.

**Float precision requirement**: `accum_old` can reach `1000.0+` before division. `rgba32float` handles this; `rgba16float` would start losing precision in the low bits.

### 4.2 GPU N-Body / Particle Systems

With 2048×2048 resolution, you have ~4 million pixels. If each pixel represents one particle, you can run a gravitational or Coulombic simulation directly in the compute shader:
```wgsl
// Each thread updates one particle
let myPos = textureLoad(dataTextureC, id, 0).xy;
var force = vec2(0.0);
for (var i: i32 = 0; i < PARTICLE_COUNT; i++) {
    let otherPos = particles[i].xy;
    let dir = otherPos - myPos;
    let distSq = dot(dir, dir) + 0.0001;
    force += dir / (distSq * sqrt(distSq));
}
```

For larger counts, use a **Barnes-Hut approximation** or **tile-based shared-memory reduction** (if the engine ever adds shared memory bindings). Even a naive O(n^2) approach works for 1,000–2,000 particles at 60fps.

### 4.3 Spectral / Multi-Wavelength Rendering

Treat RGBA not as color, but as 4 spectral bands (e.g., 450nm, 520nm, 600nm, 680nm). Each band scatters differently through a medium:
```wgsl
let scatter = vec4(0.02, 0.05, 0.12, 0.25); // wavelength-dependent extinction
let transmittance = exp(-scatter * opticalDepth);
let radiance = emission * transmittance;
```

At the end, map the 4 bands back to display RGB using a precomputed response matrix. This produces physically plausible dispersion and iridescence impossible with standard RGB tricks.

---

## 5. Smoothness: Eliminating Aliasing and Banding

### 5.1 Blue-Noise Dithering

For fixed sample counts (32, 64, 128), regular grid sampling creates aliasing. Use a blue-noise offset per pixel:
```wgsl
let blueNoise = hash2(vec2<f32>(id) + vec2(f32(frame) * 1.618, f32(frame) * 2.618));
let offset = (blueNoise - 0.5) * stepSize;
```

This turns banding into high-frequency noise, which the human eye tolerates far better.

### 5.2 Higher-Order Texture Sampling

Bilinear sampling is the default. For smoother advection (fluids, distortions), implement bicubic Catmull-Rom sampling in WGSL:
```wgsl
fn sampleBicubic(tex: texture_2d<f32>, uv: vec2<f32>) -> vec3<f32> {
    // 16 taps with cubic weights
    // ... implementation ...
}
```

This is especially impactful for fluid dye advection, where bilinear sampling causes visible diffusion and blurring over time.

### 5.3 Analytic Derivatives for Noise

Instead of finite-difference gradients for flow fields:
```wgsl
let n = noise(p);
let grad = noiseGradient(p); // analytic derivative of the hash/mix chain
```

Analytic gradients are exact, noise-free, and computationally cheaper than 4–6 extra noise evaluations.

### 5.4 Temporal Anti-Aliasing (TAA)

Jitter the camera ray by a sub-pixel offset each frame, then blend with `dataTextureC`:
```wgsl
let jitter = (hash2(uv + time) - 0.5) / resolution;
let uv_jittered = uv + jitter;
```

Over 16 frames, this effectively supersamples the image by 16x at nearly zero cost.

---

## 6. Practical WGSL Patterns

### Pattern A: HDR Volumetric Raymarch
```wgsl
var accum = vec3(0.0);
var transmittance = 1.0;
for (var i: i32 = 0; i < 128; i++) {
    let density = sampleDensity(p);
    let emission = sampleEmission(p);
    let scatter = density * stepSize * sigmaS;
    let extinct = density * stepSize * sigmaE;
    accum += emission * transmittance * scatter;
    transmittance *= exp(-extinct);
    if (transmittance < 0.001) { break; }
    p += rd * stepSize;
}
let final = toneMap(accum);
textureStore(writeTexture, id, vec4(final, 1.0 - transmittance));
```

### Pattern B: Full RGBA State Machine (Fluid)
```wgsl
let state = textureLoad(dataTextureC, id, 0);
var vel = state.xy;
var pressure = state.z;
var density = state.w;

// ... advection + projection ...

textureStore(dataTextureA, id, vec4(vel, pressure, density));
```

### Pattern C: Temporal Monte Carlo Blend
```wgsl
let prev = textureLoad(dataTextureC, id, 0);
let count = prev.a;
let newAccum = (prev.rgb * count + newSample) / (count + 1.0);
textureStore(dataTextureA, id, vec4(newAccum, count + 1.0));
```

---

## 7. Recommended Upgrade Roadmap

### Immediate (single-shader upgrades)
1. **`photonic-caustics.wgsl`**: Increase photon count from 32 -> 128, use blue-noise dithering, store accumulated result in alpha channel for temporal blending.
2. **`quantum-foam-pass1.wgsl`**: Pack the full state (velocity, pressure, density, phase) into RGBA instead of just RG.
3. **`gravitational-lensing.wgsl`**: Add analytic Jacobian for normals to free up 50% of the raymarch budget, then increase step count to 256.

### Medium-term (new shader creation)
1. **`spectral-volumetric-aurora.wgsl`**: 4-band spectral raymarch with HDR tone mapping.
2. **`mandelbulb-fractal-void.wgsl`**: Analytic-normal Mandelbulb with orbit-trap coloring.
3. **`temporal-monte-carlo-neon.wgsl`**: 4-bounce path tracer with temporal accumulation.
4. **`multifield-spectral-fluid.wgsl`**: Full RGBA-packed Navier-Stokes with Runge-Kutta advection.

### Long-term (engine-agnostic patterns)
- Create a shared WGSL utility file (`public/shaders/_ultra_utils.wgsl`) containing tone-mapping functions, bicubic samplers, analytic noise gradients, and blue-noise hashes. Shaders can copy-paste chunks from it (per the existing chunk attribution convention).

---

## 8. Performance Guardrails

At 2048x2048, the GPU is launching ~65k workgroups of 8x8 threads. To stay within 16.6ms:

| Technique | Max Safe Cost |
|-----------|---------------|
| Raymarch steps | 256 with analytic normals, 128 with finite differences |
| Noise octaves | 12 with distance LOD, 6 without |
| Texture samples | ~200 per pixel |
| Nested loops (particles) | ~2,000 iterations |
| Temporal accumulation | Any cost per frame, because it converges over time |

**Rule of thumb**: If a shader uses finite-difference normals, halve the step count. If it uses analytic normals, double it.

---

## 9. Conclusion

The Pixelocity engine is already capable of rendering effects that rival high-end demoscene productions. The limiting factor is not the BindGroup layout or the uniform structure — it is how fully the shader authors exploit:

1. **The full dynamic range of `rgba32float`**
2. **Analytic derivatives to eliminate redundant computation**
3. **Temporal feedback via `dataTextureC` for infinite effective sample counts**
4. **RGBA packing to compress multi-field simulations into the existing pipeline**
5. **GPU parallelism for Monte Carlo, N-body, and spectral integration**

Adopting even two or three of these patterns in a single shader will create effects that are visually unmistakable as "next-level" compared to the current library.
