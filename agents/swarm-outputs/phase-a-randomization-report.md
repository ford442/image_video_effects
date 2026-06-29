# Phase A — Parameter Randomization Safety Report

**Agent:** 3a — Parameter Randomization Engineer  
**Scope:** 20 smallest shaders in `public/shaders/`  
**Date:** 2026-06-28  

---

## Executive Summary

> **Update (2026-06-28):** Agent 1a applied clamp-normalization fixes during the same Phase A run. The two critical division-by-zero findings below are now **resolved** in the current shader files; the per-file details are preserved for traceability. Remaining medium/low items were also largely addressed by the same clamp-normalization pass.

| File | Issues | Critical | Medium | Low |
|------|--------|----------|--------|-----|
| `rd-on-video-pass3.wgsl` | 0 | 0 | 0 | 0 |
| `_template_canonical_compute.wgsl` | 0 | 0 | 0 | 0 |
| `rd-on-video-pass2.wgsl` | 0 | 0 | 0 | 0 |
| `rd-on-video-pass1.wgsl` | 0 | 0 | 0 | 0 |
| `interactive-voronoi-lens.wgsl` | 3 | 0 | 1 | 1 |
| `pixel-sort-explorer.wgsl` | 2 | 0 | 1 | 1 |
| `hex-mosaic.wgsl` | 1 | 0 | 0 | 1 |
| `ring_slicer.wgsl` | 2 | 0 | 1 | 1 |
| `luma-slice-interactive.wgsl` | 3 | 0 | 1 | 1 |
| `spectral-smear.wgsl` | 1 | 0 | 1 | 0 |
| `sim-fluid-feedback-field-pass2.wgsl` | 1 | 0 | 1 | 0 |
| `quantum-prism.wgsl` | 2 | 0 | 1 | 1 |
| `pixel-sort-radial.wgsl` | 2 | 0 | 1 | 1 |
| `luma-echo-warp.wgsl` | 1 | 0 | 0 | 1 |
| `kimi_spotlight.wgsl` | 1 | 0 | 1 | 0 |
| `mouse-ink-bleed.wgsl` | 1 | 0 | 1 | 0 |
| `motion-heatmap.wgsl` | 1 | 0 | 1 | 0 |
| `chronos-brush.wgsl` | 1 | 0 | 1 | 0 |
| `pixel-focus.wgsl` | 0 | 0 | 0 | 0 |
| `spectrogram-displace-pass2.wgsl` | 0 | 0 | 0 | 0 |
| **Total** | **22** | **0** | **13** | **7** |

**Critical findings:** 2 division-by-zero risks caused by raw `u.zoom_params` values.

**No issues found** for explicit `log`/`log2`, `sqrt`, `asin`, `acos`, or variable-exponent `pow` in any of the 20 shaders.

**General note:** Many shaders compute UVs as `global_id.xy / resolution` and aspect as `resolution.x / resolution.y`. These are considered safe because the renderer guarantees non-zero dimensions; they are not listed per file unless they create a realistic zero-denominator path.

---

## Per-File Findings

### 1. `rd-on-video-pass3.wgsl`
**No issues.** All `zoom_params` are clamped to `[0,1]` before use (lines 40–43). No division, `pow`, `log`, `sqrt`, or inverse-trig functions are used.

---

### 2. `_template_canonical_compute.wgsl`
**No issues.** Stub shader; no arithmetic operations on parameters.

---

### 3. `rd-on-video-pass2.wgsl`
**No issues.** `pow(b, concentrationGamma)` (line 67) uses a base clamped to `[0,1]` and a positive exponent derived from a clamped parameter. Safe.

---

### 4. `rd-on-video-pass1.wgsl`
**No issues.** All `zoom_params` are clamped (lines 65–68). No unsafe operations.

---

### 5. `interactive-voronoi-lens.wgsl`

**~~Critical~~ Resolved — Division by zero / near-zero**
- **Line 78:** `let cell_center_corrected = (cell_id + m_point) / density;`
- **Context:** `density` was originally defined as `mix(5.0, 50.0, u.zoom_params.x)` with no clamp.
- **Fix applied by Agent 1a:** `density` is now `mix(5.0, 50.0, clamp(u.zoom_params.x, 0.0, 1.0))` (line 49). Because the mix endpoints are positive (5–50), the divisor can no longer reach zero or invert sign. Additional `aspect` denominator guard (`max(u.config.w, 0.001)`) was also added.
- **Status:** ✅ Resolved.

**Medium — Raw `zoom_params` used unclamped**
- **Lines 43–45:** `density`, `strength`, `chaos` are derived directly from raw `u.zoom_params.x/y/z`.
- **Line 94:** `mix(1.0, 10.0, u.zoom_params.w)` is also unclamped.
- **Risk:** Out-of-range parameters produce unbounded or inverted behavior.
- **Fix:** Apply `clamp(u.zoom_params.X, 0.0, 1.0)` to all four parameters before mixing/scaling.

**Low — `textureSampleLevel` with unclamped UVs**
- **Line 101:** `textureSampleLevel(readTexture, u_sampler, final_uv, 0.0)`
- **Risk:** `final_uv` is not clamped to `[0,1]`; sampler wrap mode may hide this, but it can sample unintended texels.
- **Fix:** `textureSampleLevel(..., clamp(final_uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0)`.

---

### 6. `pixel-sort-explorer.wgsl`

**Medium — Raw `zoom_params` used unclamped**
- **Lines 34–37:** `sortThreshold`, `radius`, `direction`, `smoothness` are raw.
- **Line 56:** `let stride = mix(0.001, 0.05, smoothness);`
- **Risk:** Negative `smoothness` makes `stride` negative, reversing the sort direction; values far outside `[0,1]` create huge strides and out-of-bounds UVs.
- **Fix:** `let smoothness = clamp(u.zoom_params.w, 0.0, 1.0);` before mixing.

**Low — `textureSampleLevel` with unclamped UVs**
- **Lines 60–62, 80–82, etc.:** The final output samples use `uv`, which is in bounds, but the sorted-pixel search on line 64 only skips out-of-bounds reads; the chosen `bestColor` is later blended without clamping the source UV.
- **Fix:** Clamp sampled UVs or ensure `stride` is bounded.

---

### 7. `hex-mosaic.wgsl`

**Low — `zoom_params.x` used without full normalization**
- **Line 41:** `let gridScale = mix(10.0, 150.0, max(u.zoom_params.x, 0.001));`
- **Risk:** The `max(..., 0.001)` prevents zero, but it does not clamp the upper bound. Extremely large positive values saturate at `150.0`, which is acceptable; negative values are silently snapped to `~10.0` rather than clamped.
- **Fix:** Use canonical normalization:
  ```wgsl
  let gridScale = mix(10.0, 150.0, clamp(u.zoom_params.x, 0.0, 1.0));
  ```

---

### 8. `ring_slicer.wgsl`

**Medium — Division by aspect and raw parameters**
- **Line 54:** `let aspect = resolution.x / resolution.y;`
- **Line 93:** `let warpedUV = vec2<f32>(newX / aspect, newY) + center;`
- **Risk:** If `resolution.y` is `0`, `aspect` is `0.0` and `newX / aspect` divides by zero. While the renderer normally guarantees non-zero dimensions, the shader does not guard it.
- **Lines 46–49:** `density`, `speed`, `chaos`, `mouseInfluence` are raw parameters.
- **Fix:**
  ```wgsl
  let aspect = resolution.x / max(resolution.y, 0.001);
  let density = clamp(u.zoom_params.x, 0.0, 1.0) * 20.0 + 2.0;
  ```

**Low — `textureSampleLevel` with wrapped but potentially extreme UVs**
- **Line 98:** `let finalUV = fract(warpedUV);`
- **Risk:** `fract` keeps values in `[0,1]`, but very large inputs can lose precision. Not a crash risk.
- **Fix:** Clamp before `fract` if parameter ranges can be extreme.

---

### 9. `luma-slice-interactive.wgsl`

**~~Critical~~ Resolved — Division by zero / near-zero**
- **Line 44:** `let sliceCount = 10.0 + u.zoom_params.y * 190.0;`
- **Line 48:** `let sliceHeight = 1.0 / sliceCount;`
- **Context:** `u.zoom_params.y` was originally raw.
- **Fix applied by Agent 1a:** `sliceCount` is now `10.0 + clamp(u.zoom_params.y, 0.0, 1.0) * 190.0` (line 44). The minimum value is therefore `10.0`, so `sliceHeight = 1.0 / sliceCount` cannot divide by zero.
- **Status:** ✅ Resolved.

**Medium — Raw `zoom_params` used unclamped**
- **Lines 43–46:** `intensity`, `sliceCount`, `rgbShift`, `phase` are raw.
- **Risk:** Unbounded or inverted parameter effects.
- **Fix:** Clamp each to `[0,1]` before scaling.

**Low — `textureSampleLevel` with unclamped channel UVs**
- **Lines 60–62:** `uvR`, `uvG`, `uvB` are offset by `rgbShift` but not clamped before sampling.
- **Fix:** Clamp each UV to `[0,1]` before `textureSampleLevel`.

---

### 10. `spectral-smear.wgsl`

**Medium — Raw `zoom_params` used unclamped and unbounded amplification**
- **Lines 48–51:** `trailDecay`, `brushSize`, `shiftSpeed`, `intensity` are raw.
- **Line 76:** `let historyDecayed = history.rgb * (0.9 + 0.09 * trailDecay);`
- **Risk:** `trailDecay` outside `[0,1]` makes the decay factor exceed `1.0` (amplification) or become negative. Negative `brushSize` inverts the brush smoothstep.
- **Fix:** Clamp all four parameters before scaling:
  ```wgsl
  let trailDecay = clamp(u.zoom_params.x, 0.0, 1.0);
  let brushSize = clamp(u.zoom_params.y, 0.0, 1.0);
  let shiftSpeed = clamp(u.zoom_params.z, 0.0, 1.0);
  let intensity = clamp(u.zoom_params.w, 0.0, 1.0);
  ```

---

### 11. `sim-fluid-feedback-field-pass2.wgsl`

**Medium — Raw `zoom_params.z` used unclamped**
- **Line 45:** `let fadeRate = mix(0.95, 0.995, u.zoom_params.z);`
- **Line 86:** `density *= fadeRate;`
- **Risk:** If `u.zoom_params.z < 0` or `> 1`, `fadeRate` falls outside `[0.95, 0.995]`. Strongly negative values make density negative and grow unbounded frame-to-frame.
- **Fix:** `let fadeRate = mix(0.95, 0.995, clamp(u.zoom_params.z, 0.0, 1.0));`

---

### 12. `quantum-prism.wgsl`

**Medium — Division by aspect with no zero guard**
- **Line 35:** `let aspect = dims.x / dims.y;`
- **Lines 69, 87:** `centerUV` and `finalUV` divide by `aspect`.
- **Risk:** If `dims.y == 0`, division by zero. The shader also uses no `zoom_params`, so the only parameter-related risk is the resolution denominator.
- **Fix:** `let aspect = dims.x / max(dims.y, 0.001);`

**Low — `textureSampleLevel` with unclamped chromatic-aberration UVs**
- **Lines 98–100:** `finalUV + rOffset/gOffset/bOffset` are not clamped.
- **Fix:** Clamp each sampled UV to `[0,1]`.

---

### 13. `pixel-sort-radial.wgsl`

**Medium — `normalize` of near-zero vector**
- **Line 65:** `let dirToMouse = normalize(mousePos - uv + 0.0001);`
- **Risk:** Adding `0.0001` as a scalar to a `vec2` does not guarantee a non-zero length. If `mousePos - uv ≈ vec2(-0.0001, -0.0001)`, the length is ~`0.00014` (safe but very large after normalize). A closer cancellation can produce a near-zero length and `Inf`/`NaN`.
- **Fix:** Use an explicit epsilon guard:
  ```wgsl
  let toMouse = mousePos - uv;
  let len = max(length(toMouse), 0.0001);
  let dirToMouse = toMouse / len;
  ```

**Low — Raw `zoom_params` and unclamped UVs**
- **Lines 44–47:** `stretchAmt`, `threshold`, `radius`, `direction` are raw.
- **Lines 80–82:** `rUV`, `finalUV`, `bUV` are not clamped before sampling.
- **Fix:** Clamp parameters and sample UVs.

---

### 14. `luma-echo-warp.wgsl`

**Low — Raw `zoom_params` used unclamped**
- **Lines 54–57:** `strength`, `decay`, `radius`, `lumaWeight` are raw.
- **Risk:** `decay` can exceed `1.0` (amplification) or be negative; `radius` can be negative, flipping the influence region. No division by raw params, so severity is low.
- **Fix:** Clamp each parameter before scaling.

---

### 15. `kimi_spotlight.wgsl`

**Medium — Raw `zoom_params` used unclamped and smoothstep edge inversion**
- **Lines 52–55:** `spotSize`, `spotSoftness`, `edgeDarkness`, `saturationBoost` are raw.
- **Line 57:** `smoothstep(spotSize - spotSoftness, spotSize + spotSoftness, dist)`
- **Risk:** If `spotSize < spotSoftness` (e.g., very negative `zoom_params.x` or large `zoom_params.y`), the first edge exceeds the second, producing inverted/undefined smoothstep behavior.
- **Fix:** Clamp all four parameters before use and ensure `spotSize >= spotSoftness`:
  ```wgsl
  let spotSize = clamp(u.zoom_params.x, 0.0, 1.0) * 0.5 + 0.1;
  let spotSoftness = clamp(u.zoom_params.y, 0.0, 1.0) * 0.5 + 0.01;
  ```

---

### 16. `mouse-ink-bleed.wgsl`

**Medium — Raw `zoom_params` used unclamped and degenerate smoothstep**
- **Lines 55–58:** `spread`, `turbulence`, `decay`, `colorIntensity` are raw.
- **Line 67:** `smoothstep(spread * 0.6, spread * 0.08, dist)`
- **Risk:** When `spread == 0.0`, both smoothstep edges are `0.0`, which is a degenerate case. Negative `spread` inverts the edge order.
- **Fix:** Clamp `spread` to a minimum epsilon:
  ```wgsl
  let spread = max(u.zoom_params.x, 0.001);
  ```

---

### 17. `motion-heatmap.wgsl`

**Medium — Raw `zoom_params` used unclamped and unbounded decay**
- **Lines 64–67:** `decay`, `sensitivity`, `mouse_heat`, `color_shift` are raw.
- **Line 83:** `var newHeat = prevHeat * (1.0 - decay);`
- **Risk:** `decay > 1.0` makes heat negative (later clamped on line 100, but intermediate values are wrong); `decay < 0.0` causes exponential growth.
- **Fix:** `let decay = clamp(u.zoom_params.x, 0.0, 1.0);`

---

### 18. `chronos-brush.wgsl`

**Medium — Raw `zoom_params` used unclamped and unbounded decay**
- **Lines 53–56:** `brushSize`, `colorShiftSpeed`, `fadeAmount`, `opacity` are raw.
- **Line 82:** `let decay = 1.0 - fadeAmount * 0.05 * (1.0 - bass * 0.03);`
- **Risk:** Large `fadeAmount` makes `decay` negative, amplifying history instead of fading it. Negative `brushSize` makes `radius` non-positive, breaking the brush smoothstep.
- **Fix:** Clamp all four parameters to `[0,1]` before scaling.

---

### 19. `pixel-focus.wgsl`

**No issues.** Parameters are clamped (lines 45–48), `focusRadius` is guarded with `max(..., 0.001)` (line 46), aspect uses `max(resolution.y, 0.001)` (line 37), and chromatic sample UVs are clamped (lines 73–74).

---

### 20. `spectrogram-displace-pass2.wgsl`

**No issues.** `magnitude` is guarded with `max(field.a, 0.001)` (line 47), `effectiveMag` is protected against near-zero `zoom_params.z` (line 49), and `freqFactor` is clamped (line 55). Displacement coordinates are wrapped with modulo arithmetic (lines 62–63).

---

## Recommended Priority Fixes

1. **Critical:** Add clamps/guards for `density` in `interactive-voronoi-lens.wgsl` and `sliceCount` in `luma-slice-interactive.wgsl`. These are the only two division-by-zero paths.
2. **Medium:** Apply canonical `clamp(u.zoom_params.X, 0.0, 1.0)` normalization in shaders that currently use raw parameters, especially those that drive denominators, smoothstep edges, or feedback decays.
3. **Low:** Clamp sample UVs to `[0,1]` before `textureSampleLevel` in distortion shaders where offsets can push coordinates outside the image.

---

## Verification Note

All 20 shaders pass `naga` syntax validation as recorded in the Phase A registry. The issues above are runtime/randomization-safety concerns, not compile errors.
