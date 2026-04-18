# Weekly Shader Upgrade Swarm — Batch 1

> **Goal:** Upgrade WGSL shaders to fix undersized generative effects, replace naive RGB-only patterns with RGBA-aware blending, and add meaningful alpha, audio reactivity, and missing params.
> **Constraint:** Do NOT modify `Renderer.ts`, `types.ts`, or bind groups. Do NOT install new npm packages.

---

## Recently Completed (25 shaders)

These shaders have been edited, their JSONs updated where needed, and `generate_shader_lists.js` validated the changes.

| # | Shader | Batch | Changes Made |
|---|--------|-------|--------------|
| 1 | `rgb-glitch-trail` | B | Fixed workgroup size `(8,8,1)`. `dataTextureA` now stores full RGBA trail color instead of `vec4(intensity,0,0,1)`. Replaced naive `.r`/`.b` channel sampling with `vec4` blending using `glitch_weight = intensity * color.a`. |
| 2 | `chroma-shift-grid` | B | Fixed workgroup size. Replaced separate `R/G/B` sampling with full `vec4` blending where `blend = strength * c0.a`. Alpha now mixes toward the shifted samples' max alpha. |
| 3 | `selective-color` | B | Fixed workgroup size. Added `feather_exp = mix(0.5,3.0,zoom_params.w)`. Output alpha is now preserved: `final_alpha = mix(color.a * (1.0 - desat*0.3), color.a, mask)`. Renamed JSON param4 to **Mask Feather**. |
| 4 | `echo-trace` | B | Fixed workgroup size. History decay now preserves alpha: `new_history_a = history.a * decay_rate`. Brush mixing also blends alpha. `vec4(new_history_rgb, new_history_a)` written to both textures. |
| 5 | `temporal-slit-paint` | B | Fixed workgroup size. Removed `finalColor.a = 1.0` so input/video alpha is preserved through brush strokes and history decay. |
| 6 | `signal-noise` | B | Fixed workgroup size. Refactored RGB split to sample full `vec4` at each offset and blend channels using `shift_weight = clamp(...) * c0.a`. Static noise intensity is also modulated by `c0.a`. |
| 7 | `sonic-distortion` | B | Fixed workgroup size. Replaced `.r`/`.g`/`.b` sampling with full `vec4` blending controlled by `aberration_weight = mask * c0.a`. Alpha fades with distortion strength. |
| 8 | `galaxy-compute` | B | Fixed workgroup size. Generated pattern now computes `pattern_alpha = 0.4 + pattern_mask * 0.6`. Mixes overlay using `pattern_opacity = 0.3 + zoom_params.w * 0.7`. Updated JSON param4 name to **Pattern Opacity**. |
| 9 | `radial-rgb` | B | Fixed workgroup size. Replaced radial channel split with full `vec4` sampling and `blend_weight = effect * c0.a`. Original alpha is preserved in undistorted regions. |
| 10 | `luma-echo-warp` | B | Fixed workgroup size. Removed `outputColor.a = 1.0` so alpha is preserved through echo decay and warped mixing. |
| 11 | `gen-astro-kinetic-chrono-orrery` | A | Fixed workgroup size. Added param-driven hue with `plasmaBuffer` bass reactivity. Alpha fades with ray depth: `alpha = 1.0 - (t/MAX_DIST)*0.5`. |
| 12 | `gen-raptor-mini` | A | Fixed workgroup size. Added `plasmaBuffer` bass to rage mode. Body/trail now write meaningful alpha (`body=0.9+`, `trail=0.2–0.8`). Added glow halo derived from rage. |
| 13 | `gen-cosmic-web-filament` | A | Fixed workgroup size. Alpha now scales with `filDensity` so dark voids are transparent. Added `plasmaBuffer` bass reactivity to `warpStrength`. |
| 14 | `gen_psychedelic_spiral` | A | Fixed workgroup size. Replaced RGB-only patterns with smooth HSV hue rotation. Added alpha falloff at spiral edges. Center follows mouse. Added plasmaBuffer bass reactivity. |
| 15 | `cymatic-sand` | A | Fixed workgroup size. Alpha proportional to sand presence/contrast. Added writeDepthTexture height-field output. Added plasmaBuffer mids reactivity to shake frequency. |
| 16 | `gen-vitreous-chrono-chandelier` | A | Fixed workgroup size. Alpha transmission based on ray depth and transmission param. Switched audio to plasmaBuffer bass. Added writeDepthTexture pass-through. |
| 17 | `gen-xeno-botanical-synth-flora` | A | Fixed workgroup size. Added petal-edge feathering to transparent alpha. Added plasmaBuffer mids reactivity to growth/bloom. Added glowSpread param4. |
| 18 | `gen-crystal-caverns` | A | Fixed workgroup size. Added ray-depth alpha fade with fogDensity param. Mouse light modulates alpha. Added plasmaBuffer bass reactivity. |

---

## Active Queue — 0 Shaders Remaining (all completed ✅)

### Batch A — Small Generative (0 remaining — all completed ✅)

| # | Shader ID | Size | Status | Primary Upgrades |
|---|-----------|------|--------|------------------|
| A6 | `interactive-fisheye` | 2,838 | ✅ completed | Fixed workgroup size. Preserves original alpha with vignette falloff at distortion edge. Added bulge curve and edge vignette params. Added plasmaBuffer bass reactivity. |

### Batch B — Small RGB-Limited / Alpha-Oblivious Effects (0 remaining — all completed ✅)

| # | Shader ID | Size | Status | Primary Upgrades |
|---|-----------|------|--------|------------------|
| B1 | `radial-blur` | 2,781 | ✅ completed | Fixed workgroup size. Added depth pass-through. Added sample exponent, decay, and glow params. Added plasmaBuffer bass reactivity. |
| B2 | `swirling-void` | 2,944 | ✅ completed | Fixed workgroup size. Converted to full vec4 sampling with alpha preservation through black-hole darkness. Added audio reactivity param. |
| B3 | `static-reveal` | 2,865 | ✅ completed | Fixed workgroup size. dataTextureA now stores mask in alpha. Noise alpha derived from mask for smoother transition. Added noise scale param and depth pass-through. |
| B4 | `entropy-grid` | 2,941 | ✅ completed | Fixed workgroup size. Changed non-standard texture_depth_2d to texture_2d<f32>. Fixed depth pass-through. Added plasmaBuffer bass reactivity. |
| B5 | `digital-mold` | 2,981 | ✅ completed | Fixed workgroup size. Removed forced alpha=1.0. Mold blend uses mask * decayRate * color.a. Preserves original alpha outside mask. Added depth pass-through and audio reactivity. |
| B6 | `pixel-sorter` | 2,987 | ✅ completed | Fixed workgroup size. Moved threshold to zoom_params.w and intensity to zoom_params.z. Added plasmaBuffer bass reactivity. Depth pass-through already present. |
| B7 | `magnetic-field` | 3,188 | ✅ completed | Fixed workgroup size. Added plasmaBuffer bass reactivity pulsing strength. Depth pass-through already present. Updated JSON params and features. |
| B8 | `kaleidoscope` | 3,204 | ✅ completed | Fixed workgroup size. Out-of-bounds pixels now transparent with smoothstep edge softness. Preserves sampled alpha inside bounds. Added edge softness param. |
| B9 | `synthwave-grid-warp` | 2,969 | ✅ completed | Fixed workgroup size. Alpha derived from grid line intensity so lines are translucent. Added plasmaBuffer bass reactivity. Depth pass-through already present. |
| B10 | `sonar-reveal` | 3,047 | ✅ completed | Fixed workgroup size. Preserves baseColor.a through reveal/ring mix. Added depth pass-through. Added plasmaBuffer bass pulse to ring intensity. |
| B11 | `concentric-spin` | 2,983 | ✅ completed | Fixed workgroup size. Added ring gap opacity param with smoothstep alpha fade at boundaries. Added plasmaBuffer bass pulse to rotation speed. Depth pass-through already present. |
| B12 | `interactive-fresnel` | 3,069 | ✅ completed | Fixed workgroup size. Replaced naive RGB split with full vec4 sampling blended by aberration * cG.a. Added depth influence param and depth pass-through. Added plasmaBuffer bass pulse to displacement. |
| B13 | `time-slit-scan` | 2,835 | ✅ completed | Fixed workgroup size. Standardized all variable names to renderer conventions. Added plasmaBuffer bass reactivity to drift speed. Fixed ripples array size to 50. |
| B14 | `double-exposure-zoom` | 2,925 | ✅ completed | Fixed workgroup size. Replaced RGB-only screen blend with RGBA-aware blend preserving per-layer alpha. Added edge fade and audio reactivity params. Added depth pass-through and plasmaBuffer bass modulation. |
| B15 | `velocity-field-paint` | 2,906 | ✅ completed | Fixed workgroup size. Added depth pass-through. Replaced unused param4 with Audio Reactivity. Added plasmaBuffer bass reactivity to force calculation. |
| B16 | `pixel-repel` | 2,993 | ✅ completed | Fixed workgroup size. Replaced naive RGB split with full vec4 sampling and blend using aberration * c0.a. Preserves source alpha. Added plasmaBuffer bass reactivity to repel displacement. |
| B17 | `lighthouse-reveal` | 3,016 | ✅ completed | Fixed workgroup size. Reforced alpha preservation through beam reveal using texColor.a * visibility. Added depth pass-through. Added plasmaBuffer bass reactivity to beam rotation speed. |

### Batch C — Larger High-Impact Shaders (0 remaining — all completed ✅)

| # | Shader ID | Size | Status | Primary Upgrades |
|---|-----------|------|--------|------------------|
| C1 | `gen-quantum-mycelium` | 6,564 | ✅ completed | Fixed workgroup size. Added alpha falloff with edgeSoftness param. Added plasmaBuffer treble reactivity to node flicker. Added writeDepthTexture pass-through. |
| C2 | `gen-stellar-web-loom` | 6,535 | ✅ completed | Fixed workgroup size. Thread intensity drives alpha via opacity exponent param. Added plasmaBuffer bass reactivity to thread pulse. Added writeDepthTexture pass-through. |
| C3 | `gen-supernova-remnant` | 7,424 | ✅ completed | Fixed workgroup size. Replaced hard alpha=1.0 with density-based alpha via gasOpacity param. Added plasmaBuffer bass pulse to expansion/brightness. |
| C4 | `gen-cyber-terminal` | 9,107 | ✅ completed | Fixed workgroup size. Added glyph edge alpha anti-aliasing via SDF smoothstep. Added scanline bloom param. Used plasmaBuffer for cursor jitter and decode speed. Added writeDepthTexture pass-through. |
| C5 | `gen-bioluminescent-abyss` | 11,949 | ✅ completed | Fixed workgroup size. Added depth-based alpha fog via water clarity param. Bioluminescence glow affects alpha. Added plasmaBuffer bass reactivity. |
| C6 | `gen-chronos-labyrinth` | 14,095 | ✅ completed | Fixed workgroup size. Added distance-field alpha fade via atmospheric perspective param. writeDepthTexture matches ray depth. Added plasmaBuffer bass reactivity. |
| C7 | `gen-quantum-superposition` | 17,672 | ✅ completed | Fixed workgroup size. Probability-cloud alpha proportional to |ψ|² density via wavefunction opacity param. Added plasmaBuffer reactivity to quantum jitter. |

---



---

## Wolfram Alpha Reference Data (Batch 1)

> Computational constants and kernels gathered via Wolfram Alpha MCP for this week's shader upgrades.

### 1. Fresnel Reflectance (Schlick's R₀)

Normal-incidence reflectance for common materials:

| Material | n | R₀ |
|---|---|---|
| Water | 1.333 | 0.0201 |
| Glass | 1.500 | 0.0400 |
| Diamond | 2.420 | 0.1724 |

WGSL helper:
```wgsl
const FRESNEL_R0_WATER: f32 = 0.0200593122;
const FRESNEL_R0_GLASS: f32 = 0.04;
const FRESNEL_R0_DIAMOND: f32 = 0.1723949249;

fn schlickFresnel(cosTheta: f32, R0: f32) -> f32 {
    return R0 + (1.0 - R0) * pow(1.0 - cosTheta, 5.0);
}
```

### 2. Blackbody Color Temperatures

Approximate RGB values for shader use:

| Temperature (K) | RGB (normalized) |
|---|---|
| 2000 | `vec3<f32>(1.000, 0.526, 0.153)` |
| 4500 | `vec3<f32>(1.000, 0.828, 0.701)` |
| 6500 | `vec3<f32>(1.000, 0.976, 0.932)` |
| 9500 | `vec3<f32>(0.839, 0.912, 1.000)` |

### 3. Physical Constants

| Constant | Value | WGSL Symbol |
|---|---|---|
| Planck constant (h) | 6.626×10⁻³⁴ J·s | `PLANCK_H` |
| Reduced Planck constant (ℏ) | 1.055×10⁻³⁴ J·s | `PLANCK_HBAR` |
| Capillary wave speed* | 0.2477 m/s | `CAPILLARY_SPEED` |
| Sedov-Taylor radius exponent | 2/5 = 0.4 | `SEDOV_EXPONENT` |
| Rayleigh cross section (air, 550nm) | 1.188×10⁻³⁰ m² | `RAYLEIGH_SIGMA` |

*For λ=0.01m, γ=0.0728 N/m, ρ=1000 kg/m³, g=9.81 m/s²

### 4. Bessel J₀ Zeros (Airy Disk / Diffraction)

First 5 zeros for radial wave patterns:
```wgsl
const BESSEL_J0_ZEROS: array<f32, 5> = array<f32, 5>(
    2.4048255577,
    5.5200781103,
    8.6537279129,
    11.7915344390,
    14.9309177085
);
```

### 5. Golden Angle & Fibonacci

```wgsl
const GOLDEN_ANGLE: f32 = 2.3999632297; // radians, (3 - sqrt(5)) * π
const FIBONACCI: array<f32, 12> = array<f32, 12>(
    1.0, 1.0, 2.0, 3.0, 5.0, 8.0,
    13.0, 21.0, 34.0, 55.0, 89.0, 144.0
);

// Phyllotaxis spiral
fn phyllotaxis(i: f32) -> vec2<f32> {
    let r = sqrt(i) * 0.01;
    let theta = i * GOLDEN_ANGLE;
    return vec2<f32>(r * cos(theta), r * sin(theta));
}
```

### 6. Image Convolution Kernels

#### 3×3 Gaussian Blur (σ=1, normalized)
Sum = (2+√e)²/e ≈ 4.89764
```wgsl
const GAUSSIAN_3X3: array<f32, 9> = array<f32, 9>(
    0.0204, 0.1238, 0.0204,
    0.1238, 0.2042, 0.1238,
    0.0204, 0.1238, 0.0204
);
```

#### 3×3 Laplacian (edge detection)
```wgsl
const LAPLACIAN_3X3: array<f32, 9> = array<f32, 9>(
    0.0,  1.0, 0.0,
    1.0, -4.0, 1.0,
    0.0,  1.0, 0.0
);
```

#### Sobel Operators
```wgsl
const SOBEL_GX: array<f32, 9> = array<f32, 9>(
    -1.0, 0.0, 1.0,
    -2.0, 0.0, 2.0,
    -1.0, 0.0, 1.0
);
const SOBEL_GY: array<f32, 9> = array<f32, 9>(
    -1.0, -2.0, -1.0,
     0.0,  0.0,  0.0,
     1.0,  2.0,  1.0
);
```

### 7. Color Science & Fog Formulas

```wgsl
// Linear ↔ sRGB conversion
fn linearToSRGB(c: f32) -> f32 {
    return select(1.055 * pow(c, 1.0/2.4) - 0.055, c * 12.92, c <= 0.0031308);
}

fn sRGBToLinear(c: f32) -> f32 {
    return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
}

// Exponential fog
fn expFog(color: vec3<f32>, fogColor: vec3<f32>, depth: f32, density: f32) -> vec3<f32> {
    let fogFactor = exp(-depth * density);
    return mix(fogColor, color, fogFactor);
}

// Premultiplied alpha blend (over operator)
fn blendPremultiplied(dst: vec4<f32>, src: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(dst.rgb + src.rgb * (1.0 - dst.a), dst.a + src.a * (1.0 - dst.a));
}
```

### 8. Signed Distance Functions (SDF)

```wgsl
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// Polynomial smooth minimum for SDF blending
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
```

### 9. Seawater Attenuation Coefficients

| Wavelength | Coefficient (m⁻¹) |
|---|---|
| 450 nm (blue) | 0.03 |
| 550 nm (green) | 0.08 |
| 650 nm (red) | 0.35 |

```wgsl
const WATER_ATTENUATION: vec3<f32> = vec3<f32>(0.35, 0.08, 0.03); // R, G, B
```
## Detailed Code Suggestions

### A1 — `gen_psychedelic_spiral`
- Fix `@workgroup_size(16, 16, 1)` → `(8, 8, 1)`.
- If the shader computes color as `vec3<f32>(...)`, append alpha based on distance from spiral center:
  ```wgsl
  let alpha = 1.0 - smoothstep(0.3, 0.8, dist_from_center);
  textureStore(writeTexture, coords, vec4<f32>(col, alpha));
  ```
- Add mouse-driven focal point by offsetting the spiral center with `u.zoom_config.yz`.

### A2 — `cymatic-sand`
- Fix workgroup size.
- Where particles are written, set alpha proportional to speed:
  ```wgsl
  let speed_alpha = clamp(length(velocity), 0.0, 1.0);
  textureStore(writeTexture, coords, vec4<f32>(col, speed_alpha));
  ```
- Write depth based on particle height/pseudo-Z:
  ```wgsl
  textureStore(writeDepthTexture, coords, vec4<f32>(speed_alpha, 0.0, 0.0, 0.0));
  ```
- Add `plasmaBuffer[0].x` (bass) to the vibration frequency.

### A3 — `gen-vitreous-chrono-chandelier`
- Fix workgroup size.
- For glass surfaces, compute a Fresnel-like term and use it to lower alpha:
  ```wgsl
  let fresnel = pow(1.0 - abs(dot(normal, rd)), 2.0);
  let transmission = u.zoom_params.w;
  let alpha = mix(1.0, 0.4, fresnel * transmission);
  textureStore(writeTexture, coords, vec4<f32>(col, alpha));
  ```
- Add param4 in JSON as "Transmission" (0.0–1.0).

### A4 — `gen-xeno-botanical-synth-flora`
- Fix workgroup size.
- At petal edges (where `dist_to_edge` is small), feather alpha:
  ```wgsl
  let edge_alpha = smoothstep(0.0, 0.05, dist_to_edge);
  textureStore(writeTexture, coords, vec4<f32>(col, edge_alpha));
  ```
- Add `plasmaBuffer[0].y` (mids) to the growth/bloom pulse multiplier.

### A5 — `gen-crystal-caverns`
- Fix workgroup size.
- After raymarching, fade alpha with depth:
  ```wgsl
  let fog = u.zoom_params.w; // fog density
  let alpha = exp(-t * 0.05 * fog);
  textureStore(writeTexture, coords, vec4<f32>(col, alpha));
  ```
- Add JSON param4 "Fog Density".

### A6 — `interactive-fisheye`
- Fix workgroup size.
- The shader already samples full `vec4`, but can be enhanced with a vignette alpha at the radius edge:
  ```wgsl
  let edge_fade = smoothstep(radius, radius * 0.8, dist);
  color.a = color.a * edge_fade;
  textureStore(writeTexture, vec2<i32>(global_id.xy), color);
  ```

### B1 — `radial-blur`
- Fix workgroup size.
- The accumulator already averages full `vec4` samples, so alpha is preserved correctly. Add depth pass-through:
  ```wgsl
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  ```
- Add `zoom_params.w` as "Sample Curve" to control `t` exponent:
  ```wgsl
  let curve = 0.5 + u.zoom_params.w * 2.0;
  let t = pow(f32(i) / f32(samples - 1), curve);
  ```

### B2 — `swirling-void`
- Fix workgroup size.
- Replace `.rgb` sampling and forced alpha:
  ```wgsl
  var color = textureSampleLevel(readTexture, u_sampler, new_uv, 0.0);
  // Apply darkness to rgb only
  if (dist < hole_size) {
      color.rgb = vec3<f32>(0.0);
  } else if (dist < hole_size * 2.0) {
      color.rgb *= smoothstep(hole_size, hole_size * 2.0, dist);
  }
  textureStore(writeTexture, coord, color);
  ```

### B3 — `static-reveal`
- Fix workgroup size.
- Store full mask in alpha:
  ```wgsl
  textureStore(dataTextureA, global_id.xy, vec4<f32>(mask, 0.0, 0.0, mask));
  ```
- Let noise alpha follow the inverse of the mask for smoother transitions:
  ```wgsl
  let noiseColor = vec4<f32>(vec3<f32>(noiseVal), 1.0 - mask);
  let finalColor = mix(noiseColor, videoColor, mask);
  ```

### B4 — `entropy-grid`
- Fix workgroup size.
- Change `readDepthTexture` binding type from `texture_depth_2d` to `texture_2d<f32>` (match standard bindings) and update depth read:
  ```wgsl
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  ```

### B5 — `digital-mold`
- Fix workgroup size.
- Preserve original alpha and blend mold with it:
  ```wgsl
  let moldAlpha = mask * decayRate * color.a;
  let decayed = mix(pixelColor, moldColor.rgb, colorShift);
  color = mix(color, vec4<f32>(decayed, 1.0), moldAlpha);
  ```

### B6 — `pixel-sorter`
- Fix workgroup size.
- Already preserves alpha. Add depth pass-through:
  ```wgsl
  let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
  ```
- Add `zoom_params.w` as "Sort Threshold" to replace mouse-Y dependency:
  ```wgsl
  let threshold = u.zoom_params.w;
  ```

### B7 — `magnetic-field`
- Fix workgroup size.
- Add depth pass-through and audio reactivity:
  ```wgsl
  let bass = plasmaBuffer[0].x;
  let strength = u.zoom_params.x * (1.0 + bass * 0.5);
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
  ```

### B8 — `kaleidoscope`
- Fix workgroup size.
- Make out-of-bounds transparent:
  ```wgsl
  var color = vec4<f32>(0.0, 0.0, 0.0, 0.0);
  if (final_uv.x >= 0.0 && final_uv.x <= 1.0 && final_uv.y >= 0.0 && final_uv.y <= 1.0) {
      color = textureSampleLevel(readTexture, u_sampler, final_uv, 0.0);
  }
  ```
- Add `zoom_params.w` as "Edge Softness" if a new param slot is desired (currently `w` is unused).

### B9 — `synthwave-grid-warp`
- Fix workgroup size.
- Derive alpha from grid line brightness so video shows through dark grid cells:
  ```wgsl
  let alpha = 0.2 + gridLine * 0.8;
  var finalColor = mix(videoColor * 0.5, gridColor, gridLine);
  finalColor += vec3(0.0, 1.0, 1.0) * warp * 2.0;
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
  ```
- Add depth pass-through.

### B10 — `sonar-reveal`
- Fix workgroup size.
- Preserve input alpha through the reveal:
  ```wgsl
  var finalColor = mix(dimColor, baseColor.rgb, reveal);
  finalColor = finalColor + ringColorVec * ring * intensity;
  let final_alpha = mix(baseColor.a * 0.5, baseColor.a, reveal);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, final_alpha));
  ```

### B11 — `concentric-spin`
- Fix workgroup size.
- Add ring-gap opacity using `zoom_params.w`:
  ```wgsl
  let gap_opacity = u.zoom_params.w;
  let ring_frac = fract(ringVal);
  let in_gap = smoothstep(0.45, 0.55, ring_frac);
  color.a = mix(color.a, color.a * gap_opacity, in_gap);
  textureStore(writeTexture, vec2<i32>(global_id.xy), color);
  ```
- Add depth pass-through.

### B12 — `interactive-fresnel`
- Fix workgroup size.
- Replace naive RGB split with full `vec4` blending:
  ```wgsl
  let c0 = textureSampleLevel(readTexture, u_sampler, baseUV, 0.0);
  let c_r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0);
  let c_b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0);
  let ab_weight = aberration * c0.a;
  var finalColor = c0;
  finalColor.r = mix(c0.r, c_r.r, ab_weight);
  finalColor.b = mix(c0.b, c_b.b, ab_weight);
  textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
  ```
- Add depth pass-through.

### B13 — `time-slit-scan`
- Fix workgroup size.
- Rename texture variables for consistency (optional but recommended):
  ```wgsl
  // Change: input_texture -> readTexture, output_texture -> writeTexture,
  // data_texture_a -> dataTextureA, data_texture_c -> dataTextureC,
  // depth_texture_read -> readDepthTexture, depth_texture_write -> writeDepthTexture
  ```
- Add audio reactivity to drift:
  ```wgsl
  let bass = plasma_buffer[0].x;
  let drift = vec2<f32>(drift_speed * 0.1 * (1.0 + bass), 0.0);
  ```

### B14 — `double-exposure-zoom`
- Fix workgroup size.
- Replace hard alpha with screen-blended alpha:
  ```wgsl
  let blended_rgb = 1.0 - (1.0 - col1.rgb) * (1.0 - col2.rgb);
  let blended_alpha = 1.0 - (1.0 - col1.a) * (1.0 - col2.a);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(blended_rgb, blended_alpha));
  ```
- Add depth pass-through.

### B15 — `velocity-field-paint`
- Fix workgroup size.
- Add `plasmaBuffer` bass to force:
  ```wgsl
  let bass = plasmaBuffer[0].x;
  let force = u.zoom_params.z * 0.5 * (1.0 + bass);
  ```
- Add depth pass-through:
  ```wgsl
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
  textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
  ```

### B16 — `pixel-repel`
- Fix workgroup size.
- Replace naive RGB split with full `vec4` blending:
  ```wgsl
  let c0 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let c_r = textureSampleLevel(readTexture, u_sampler, clamp(uv - displacement * (1.0 + aberration), vec2(0.0), vec2(1.0)), 0.0);
  let c_g = textureSampleLevel(readTexture, u_sampler, clamp(uv - displacement, vec2(0.0), vec2(1.0)), 0.0);
  let c_b = textureSampleLevel(readTexture, u_sampler, clamp(uv - displacement * (1.0 - aberration), vec2(0.0), vec2(1.0)), 0.0);
  let ab_weight = aberration * c0.a;
  var color = c0;
  color.r = mix(c0.r, c_r.r, ab_weight);
  color.g = mix(c0.g, c_g.g, ab_weight);
  color.b = mix(c0.b, c_b.b, ab_weight);
  textureStore(writeTexture, vec2<i32>(global_id.xy), color);
  ```

### B17 — `lighthouse-reveal`
- Fix workgroup size.
- Preserve input alpha:
  ```wgsl
  let finalColor = mix(texColor.rgb * ambient, texColor.rgb, mask);
  let finalAlpha = mix(texColor.a * ambient, texColor.a, mask);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, finalAlpha));
  ```

### C1 — `gen-quantum-mycelium`
- Add alpha falloff at thread edges:
  ```wgsl
  let edge_dist = abs(d - thread_radius);
  let alpha = 1.0 - smoothstep(0.0, 0.02, edge_dist);
  ```
- Add `plasmaBuffer[0].z` (treble) to node brightness/flicker.

### C2 — `gen-stellar-web-loom`
- Let thread intensity drive alpha:
  ```wgsl
  let opacity_exp = u.zoom_params.w * 3.0 + 0.5;
  let alpha = pow(intensity, opacity_exp);
  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
  ```
- Add JSON param4 "Thread Opacity Exponent" and `plasmaBuffer` bass reactivity.

### C3 — `gen-supernova-remnant`
- Replace hard `alpha = 1.0` with density-based alpha:
  ```wgsl
  let density = smoothstep(0.0, 1.0, nebula_val);
  let alpha = density * 0.7 + 0.3;
  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
  ```
- Add `plasmaBuffer[0].x` to expansion radius.

### C4 — `gen-cyber-terminal`
- Add glyph edge AA using smoothstep against glyph SDF:
  ```wgsl
  let glyph_sdf = ...; // existing distance
  let glyph_alpha = smoothstep(0.05, 0.0, glyph_sdf);
  textureStore(writeTexture, id.xy, vec4<f32>(col, glyph_alpha));
  ```
- Add param4 "Scanline Bloom" mapped to `zoom_params.w`.
- Drive cursor jitter with `plasmaBuffer[0].x`.

### C5 — `gen-bioluminescent-abyss`
- Add depth-based fog alpha:
  ```wgsl
  let clarity = u.zoom_params.w * 5.0 + 0.1;
  let alpha = exp(-t * 0.05 * clarity);
  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
  ```
- Add JSON param4 "Water Clarity".

### C6 — `gen-chronos-labyrinth`
- Add distance-field alpha fade:
  ```wgsl
  let atmo = u.zoom_params.w; // atmospheric perspective
  let alpha = exp(-t * 0.02 * atmo);
  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
  ```
- Add JSON param4 "Atmospheric Perspective".

### C7 — `gen-quantum-superposition`
- Probability-cloud alpha:
  ```wgsl
  let psi_density = length(quantum_val);
  let opacity = u.zoom_params.w * 2.0 + 0.2;
  let alpha = clamp(psi_density * opacity, 0.0, 1.0);
  textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
  ```
- Add JSON param4 "Wavefunction Opacity".

---

## Execution Checklist (for swarm agents)

For each shader in the Active Queue:
- [ ] Read WGSL and JSON.
- [ ] Apply the specific upgrades above.
- [ ] Update JSON if new params/features are added.
- [ ] Run `node scripts/generate_shader_lists.js` and fix any errors.
- [ ] Mark the shader as **DONE** in this file and move it to the "Recently Completed" table.
- [ ] If the active queue drops below 25, add new candidates from the smallest-shaders list to replenish.

## Candidate Pool for Replenishment

Next smallest shaders not yet in any batch:
- `phosphor-decay` (3,215)
- `bitonic-sort` (3,025)
- `temporal-rgb-smear` (3,065)
- `elastic-chromatic` (3,089)
- `waveform-glitch` (3,117)
- `data-slicer-interactive` (3,163)
- `pixel-stretch-cross` (3,163)
- `interactive-magnetic-ripple` (3,166)
- `luma-pixel-sort` (3,192)
- `pixel-depth-sort` (3,195)
- `pixel-sand` (3,208)
- `crt-magnet` (3,230)
- `scan-distort-gpt52` (3,236)
- `digital-lens` (3,238)
- `chromatic-mosaic-projector` (3,242)
- `chrono-slit-scan` (3,242)
- `mosaic-reveal` (3,247)
- `quad-mirror` (3,256)
- `spiral-lens` (3,266)
- `tile-twist` (3,267)
- `page-curl-interactive` (3,284)
- `tesseract-fold` (3,286)
- `polar-warp-interactive` (3,287)
- `echo-ripple` (3,307)
- `scanline-wave` (3,315)
- `quantum-ripples` (3,331)
- `oscilloscope-overlay` (3,340)
- `spectral-brush` (3,353)
- `magnetic-interference` (3,355)
- `voxel-grid` (3,357)
- `polka-dot-reveal` (3,362)
- `scanline-sorting` (3,363)
- `pixel-scattering` (3,366)
- `neon-cursor-trace` (3,373)
- `directional-glitch` (3,382)
- `stereoscopic-3d` (3,386)
- `cyber-ripples` (3,390)
- `quantized-ripples` (3,400)
- `thermal-touch` (3,401)
- `data-scanner` (3,405)
- `vertical-slice-wave` (3,411)
- `phantom-lag` (3,412)
- `xerox-degrade` (3,425)
