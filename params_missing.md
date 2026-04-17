# Shaders Missing Custom Uniform Params (App Sliders)

> **Context:** The Pixelocity renderer exposes **4 float sliders** via `zoom_params` (`x`, `y`, `z`, `w`). After removing non-functioning `zoom_*` param references from WGSL, **45 shader definitions** still have fewer than 4 params.
>
> This document lists them and provides **concrete automation suggestions** for each missing slot.

---

## Summary

| Severity | Count | Criteria |
|----------|-------|----------|
| 🔴 Critical | 10 | WGSL actively reads `zoom_params` slots that are **not declared in JSON**, meaning users get `0.0` with no slider control |
| 🟠 High | 5 | 0 params defined — completely uncontrollable via sliders (some may also be missing WGSL files) |
| 🟡 Medium | 24 | 1–2 params defined — large gaps in controllability |
| 🟢 Low | 6 | 3 params defined — only needs 1 more to be complete |

**Total affected:** 45 shaders (~6.3% of all 709 definitions)

---

## 🔴 Critical — WGSL Reads Undeclared Param Slots

These shaders reference `zoom_params.x/y/z/w` in their WGSL, but the JSON manifest does not declare those sliders. Users cannot control the feature because the shader receives `0.0` (or an unlabeled generic `zoom_params`).

| # | Shader ID | Category | JSON Path | Missing Slots | What To Add |
|---|-----------|----------|-----------|---------------|-------------|
| 1 | `quantum-fractal` | artistic | `shader_definitions/artistic/quantum-fractal.json` | x, y, z | **Scale** (x): `zoom_params.x` controls fractal scale. **Iterations** (y): `zoom_params.y` controls iteration depth. **Entanglement** (z): `zoom_params.z` controls entanglement strength. |
| 2 | `infinite-zoom` | distortion | `shader_definitions/distortion/infinite-zoom.json` | x, y, w | **Zoom Speed** (x): `zoom_params.x` is already read for speed. **Param A** (y): `zoom_params.y` is already read for hyperbolic deformation. **Max Iterations** (w): `zoom_params.w` is already read for loop limit. |
| 3 | `spectral-vortex` | distortion | `shader_definitions/distortion/spectral-vortex.json` | x, y, z | **Twist Scale** (x): `zoom_params.x` is already read. **Distortion Step** (y): `zoom_params.y` is already read. **Color Shift** (z): `zoom_params.z` is already read. |
| 4 | `chroma-threads` | image | `shader_definitions/image/chroma-threads.json` | x, y, z | **Thread Density** (x): `zoom_params.x` is already read for thread count. **Vibration Amp** (y): `zoom_params.y` is already read for wave strength. **RGB Split** (z): `zoom_params.z` is already read for chromatic offset. |
| 5 | `spectral-mesh` | image | `shader_definitions/image/spectral-mesh.json` | x, y, z, w | **Grid Density** (x): `zoom_params.x` is already read. **Displacement Strength** (y): `zoom_params.y` is already read. **Mouse Radius** (z): `zoom_params.z` is already read. **Color Shift** (w): `zoom_params.w` is already read. |
| 6 | `scan-distort` | retro-glitch | `shader_definitions/retro-glitch/scan-distort.json` | x, y, z, w | **Block Size** (x): `zoom_params.x` is already read. **Quantization** (y): `zoom_params.y` is already read. **Motion Vector Vis** (z): `zoom_params.z` is already read. **Glitch Frequency** (w): `zoom_params.w` is already read. |
| 7 | `chromatic-manifold` | artistic | `shader_definitions/artistic/chromatic-manifold.json` | w | **Neighborhood Scale** (w): `zoom_params.w` is already read on line 110 for curvature; rename to something meaningful or split into **Curvature Scale** (w) and add **Search Radius** as a new concept if possible. |
| 8 | `engraving-stipple` | artistic | `shader_definitions/artistic/engraving-stipple.json` | w | **Burr Texture** (w): `zoom_params.w` is already read on line 51 for engraving burr amount. |
| 9 | `directional-glitch` | interactive-mouse | `shader_definitions/interactive-mouse/directional-glitch.json` | w | **Angle Bias** (w): `zoom_params.w` is already read on line 38 for glitch direction rotation. |
| 10 | `glass-bead-curtain` | interactive-mouse | `shader_definitions/interactive-mouse/glass-bead-curtain.json` | w | **Glass Density** (w): `zoom_params.w` is already read on line 41 for Beer-Lambert absorption. |

---

## 🟠 High — 0 Params Defined

These have **no sliders at all**. Several are generative placeholders that may also lack WGSL files.

| # | Shader ID | Category | JSON Path | Suggested Full Param Set |
|---|-----------|----------|-----------|--------------------------|
| 1 | `gen-bioluminescent-aether-pulsar` | generative | `shader_definitions/generative/gen-bioluminescent-aether-pulsar.json` | **Camera Distance**, **Beam Tightness**, **Core Size**, **Glow Hue Shift** |
| 2 | `gen-celestial-glass-tornado` | generative | `shader_definitions/generative/gen-celestial-glass-tornado.json` | **Spin Speed**, **Glass Thickness**, **Chaos**, **Opacity** (WGSL already uses 4 params; needs JSON sync) |
| 3 | `gen-ethereal-quantum-medusa` | generative | `shader_definitions/generative/gen-ethereal-quantum-medusa.json` | **Tentacle Count**, **Pulse Speed**, **Glow**, **Turbulence** (WGSL already uses 4) |
| 4 | `gen-graviton-plasma-lotus` | generative | `shader_definitions/generative/gen-graviton-plasma-lotus.json` | **Petals**, **Rotation**, **Plasma Intensity**, **Bloom** (WGSL already uses 4) |
| 5 | `gen-nebular-chrono-astrolabe` | generative | `shader_definitions/generative/gen-nebular-chrono-astrolabe.json` | **Gear Speed**, **Star Density**, **Nebula Color**, **Vignette** (WGSL already uses 4) |

> **Note:** The 4 generative shaders above (except `gen-bioluminescent-aether-pulsar`) already reference all 4 `zoom_params` in their WGSL. The highest-priority fix is simply updating their JSONs to expose the params already wired in.

---

## 🟡 Medium — 1–2 Params Defined

### 1 Param (9 shaders)

| # | Shader ID | Category | Existing Param | Missing Slots | Suggested Additions |
|---|-----------|----------|----------------|---------------|---------------------|
| 1 | `quantum-fractal` | artistic | `edge_glow` (w) | x, y, z | **Scale** (x), **Iterations** (y), **Entanglement** (z) — *also Critical* |
| 2 | `infinite-zoom` | distortion | `perspective_strength` (z) | x, y, w | **Zoom Speed** (x), **Param A** (y), **Max Iterations** (w) — *also Critical* |
| 3 | `spectral-vortex` | distortion | `color_dispersion` (w) | x, y, z | **Twist Scale** (x), **Distortion Step** (y), **Color Shift** (z) — *also Critical* |
| 4 | `chroma-threads` | image | `zoom_params` (unmapped) | x, y, z | **Thread Density** (x), **Vibration Amp** (y), **RGB Split** (z) — *also Critical* |
| 5 | `spectral-mesh` | image | `zoom_params` (unmapped) | x, y, z, w | **Grid Density** (x), **Displacement** (y), **Mouse Radius** (z), **Color Shift** (w) — *also Critical* |
| 6 | `digital-haze` | interactive-mouse | `zoom_params` (unmapped) | w | **Haze Density** (w): replaces extinction coefficient `SIGMA_T_HAZE = 1.2`. Alternative: **Step Size** (w) for ray-march granularity. |
| 7 | `magnetic-ring` | interactive-mouse | `zoom_params` (unmapped) | w | **Ring Thickness** (w): replaces `thickness = 0.1`. Alternative: **Twist Frequency** (w) for the `sin(dist * 20.0)` multiplier. |
| 8 | `scan-distort` | retro-glitch | `zoom_params` (unmapped) | x, y, z, w | **Block Size** (x), **Quantization** (y), **Motion Vector Vis** (z), **Glitch Frequency** (w) — *also Critical* |
| 9 | `spectral-rain` | visual-effects | `zoom_params` (unmapped) | w | **Rain Angle Scale** (w): replaces `angleVal * 0.5`. Alternative: **Brightness Boost** (w) for drop intensity multiplier. |

### 2 Params (10 shaders)

| # | Shader ID | Category | Existing Params | Missing Slots | Suggested Additions |
|---|-----------|----------|-----------------|---------------|---------------------|
| 1 | `complex-exponent-warp` | distortion | `zoomParam1` (Scale), `zoomParam2` (Spiral rotation) | z, w | **Exponent Spread** (z): replaces hardcoded `6.0` in `(mouse.x - 0.5) * 6.0`. **UV Warp Scale** (w): replaces hardcoded `0.5` in `result_z * 0.5 + 0.5`. |
| 2 | `ascii-lens` | interactive-mouse | `radius`, `density` | z, w | **Glyph Line Width** (z): replaces `width = 0.1`. **Brightness Threshold Bias** (w): shifts the `0.8, 0.6, 0.4, 0.25, 0.1` luma thresholds. |
| 3 | `fabric-zipper` | interactive-mouse | `teeth_density`, `spread` | z, w | **Weave Frequency** (z): replaces `sin(uv * 200.0)`. **Tooth Jaggedness** (w): replaces `tooth_amp = 0.02`. |
| 4 | `quad-mirror` | interactive-mouse | `mode`, `zoom` | z, w | **Rotation** (z): adds a rotate matrix before `abs()` mirroring. **Mirror Sectors** (w): replaces fixed 4-way mirror with variable sector count (2–8). |
| 5 | `bayer-dither-interactive` | retro-glitch | `zoomParam1` (Quantization), `zoomParam2` (Contrast) | z, w | **Dither Spread** (z): scales the Bayer threshold spread. **Pixel Scale Max** (w): replaces `mix(1.0, 16.0, mouse.y)` max block size. |
| 6 | `neon-edges` | retro-glitch | `edgeThreshold`, `neonIntensity` | z, w | **Layer Count** (z): replaces hardcoded loop count `5`. **Flow Distortion** (w): replaces hardcoded `0.015` noise warp multiplier. |
| 7 | `cyber-physical-portal` | visual-effects | `radius`, `glitch_speed` | z, w | **Glow Sharpness** (z): replaces `exp(-abs(dist - radius) * 20.0)` multiplier. **Grid Density** (w): replaces `fract(uv * 20.0)` interior grid. |
| 8 | `electric-contours` | visual-effects | `param1`, `param2` | z, w | **Edge Threshold** (z): remaps `smoothstep(0.1, 0.4, edge)` bounds. **Spark Speed** (w): replaces `t * 2.0` noise animation speed. |

---

## 🟢 Low — 3 Params Defined (Needs Just 1 More)

| # | Shader ID | Category | Existing Params | Suggested 4th Param |
|---|-----------|----------|-----------------|---------------------|
| 1 | `perspective-tilt` | distortion | `tilt_sensitivity`, `distance_(fov)`, `y_axis_tilt_(pitch)` | **Plane Scale / Zoom** (w): scales `u_plane` and `v_plane` before remapping to UV. Alternative: **Roll Angle** (w) for Z-axis rotation. |
| 2 | `predator-camouflage` | distortion | `radius`, `distortion`, `shimmer` | **Noise Scale** (w): replaces `noise(uv * 10.0)` multiplier (range 5–40). Alternative: **Edge Highlight** (w) for cloak boundary visibility. |
| 3 | `prismatic-mosaic` | distortion | `tileSize`, `speed`, `satBoost` | **Fog Density** (w): `zoom_params.w` is already read on line 251 but omitted from JSON. Alternative: **Flow Displacement** (w) for the `0.015` noise UV warp. |
| 4 | `gen-isometric-city` | generative | `density`, `speed`, `glow` | **Building Height Scale** (w): replaces hardcoded `8.0` in `pow(h_rnd, 2.0) * 8.0`. Alternative: **Fog Density** (w) for the `0.02` atmospheric extinction. |
| 5 | `volumetric-cloud-nebula` | generative | `cloudDensity`, `colorShift`, `cameraDistance` | **Extinction / Scattering** (w): replaces `SIGMA_T_NEBULA = 1.2`. Alternative: **Step Size** (w) for the `0.15` ray-march granularity. |
| 6 | `cyber-hex-armor` | interactive-mouse | `hex_size`, `glow_intensity`, `reveal_radius` | **Border Thickness** (w): replaces `border = 0.05`. Alternative: **Circuit Detail Density** (w) for the `10.0` circuit-trace frequency. |
| 7 | `interactive-voronoi-lens` | interactive-mouse | `cell_density`, `lens_strength`, `chaos` | **Lens Curve / Bulge Frequency** (w): replaces `sin(dist * 3.1415)`. Alternative: **Mouse Boost** (w) for the `2.0` proximity amplification multiplier. |
| 8 | `pixel-depth-sort` | interactive-mouse | `depth`, `shadows`, `layers` | **Shadow Threshold** (w): replaces `luma < layer_height + 0.05` rim-shadow thickness. Alternative: **Layer Bias Curve** (w) for nonlinear depth-step distribution. |
| 9 | `radial-hex-lens` | interactive-mouse | `scale`, `radius`, `distortion` | **Hex Edge Hardness** (w): replaces `smoothstep(hex_size * 0.5, hex_size * 0.45, ...)`. Alternative: **Magnification Multiplier** (w) for the `0.5` lens strength cap. |
| 10 | `rgb-delay-brush` | interactive-mouse | `persistence`, `split`, `brush_radius` | **Alpha Absorption Scale** (w): replaces `mask * split * 5.0` Beer-Lambert scalar. Alternative: **Brush Falloff Sharpness** (w) for the `smoothstep(radius, radius * 0.5, dist)` ratio. |
| 11 | `rgb-iso-lines` | interactive-mouse | `thickness`, `frequency`, `parallax` | **Background Opacity** (w): replaces the hardcoded `0.1` multiplier on the original image behind contours. Alternative: **Line Softness** (w) for the `0.02` antialiasing epsilon. |
| 12 | `sphere-projection` | interactive-mouse | `zoom`, `rotation`, `light` | **Ambient Light** (w): replaces `ambient = 0.2`. Alternative: **Sphere Radius** (w) for the fixed `radius = 1.0`. |
| 13 | `x-ray-reveal` | interactive-mouse | `lens_size`, `edge_strength`, `contrast` | **Lens Edge Softness** (w): replaces `blur = 0.05` in the lens mask smoothstep. Alternative: **Background Dimming** (w) for the fixed `0.8` outside-lens multiplier. |
| 14 | `cyber-terminal-ascii` | retro-glitch | `density`, `color_mode`, `glow` | **Decoder Radius** (w): replaces `decoder_radius = 0.15`. Alternative: **Glyph Gamma** (w) for the `pow(luma, 1.2)` brightness remap. |
| 15 | `split-flap-display` | simulation | `rows`, `radius`, `auto_speed` | **Damping / Friction** (w): replaces velocity multiplier `0.92`. Alternative: **Spring Strength** (w) for the `0.02` snap-to-stop torque. |
| 16 | `temporal-rgb-smear` | visual-effects | `green_lag`, `blue_lag`, `feedback` | **Mouse Influence Radius** (w): replaces `smoothstep(0.0, 0.3, dist)`. Alternative: **Red Channel Lag** (w) to lag the currently instantaneous red channel too. |
| 17 | `zipper-reveal` | visual-effects | `zipper_width`, `tooth_size`, `angle` | **Tooth Amplitude** (w): replaces `tooth_size * 0.5` interlock depth. Alternative: **Void Brightness** (w) for the exposed gap color `0.05`. |

---

## Shader-by-Shader Automation Details

### `quantum-fractal`
- **Missing:** x, y, z
- **WGSL evidence:** Reads `zoom_params.x` (scale), `y` (iterations), `z` (entanglement strength).
- **Action:** Add JSON params: Scale (0.0–2.0), Iterations (0.0–1.0 mapped to 1–50), Entanglement (0.0–1.0).

### `infinite-zoom`
- **Missing:** x, y, w
- **WGSL evidence:** Reads `zoom_params.x` (zoom_speed), `y` (param_a), `w` (max_iterations).
- **Action:** Add JSON params for all three. Rename existing `perspective_strength` (z) if needed to **Rotation** since z is actually rotation.

### `spectral-vortex`
- **Missing:** x, y, z
- **WGSL evidence:** Reads `zoom_params.x` (twist_scale), `y` (distortion_step), `z` (color_shift).
- **Action:** Add JSON params: Twist Scale, Distortion Step, Color Shift.

### `chroma-threads`
- **Missing:** x, y, z
- **WGSL evidence:** Reads `zoom_params.x` (thread_density), `y` (vibration_amp), `z` (rgb_split).
- **Action:** Add 3 labeled params. The existing generic `zoom_params` entry is useless.

### `spectral-mesh`
- **Missing:** x, y, z, w
- **WGSL evidence:** Reads all 4 slots: Grid Density (x), Displacement Strength (y), Mouse Radius (z), Color Shift (w).
- **Action:** Replace the single generic `zoom_params` entry with 4 named params.

### `scan-distort`
- **Missing:** x, y, z, w
- **WGSL evidence:** Reads all 4 slots: Block Size (x), Quantization (y), Motion Vector Visibility (z), Glitch Frequency (w).
- **Action:** Replace the single generic `zoom_params` entry with 4 named params.

### `digital-haze`
- **Missing:** w
- **WGSL evidence:** `x`=pixelStrength, `y`=clearRadius, `z`=noiseAmt; `w` is free.
- **Action:** Add **Haze Density** (w): maps to `SIGMA_T_HAZE` (range 0.2–3.0).

### `magnetic-ring`
- **Missing:** w
- **WGSL evidence:** `x`=baseRadius, `y`=strength, `z`=pulseSpeed; `w` is free.
- **Action:** Add **Ring Thickness** (w): replaces hardcoded `thickness = 0.1` (range 0.01–0.3).

### `spectral-rain`
- **Missing:** w
- **WGSL evidence:** `x`=density, `y`=chromaticStr, `z`=trailLen; `w` is free.
- **Action:** Add **Rain Angle Scale** (w): replaces `angleVal * 0.5` (range 0.0–1.5).

### `complex-exponent-warp`
- **Missing:** z, w
- **Action:** Add **Exponent Spread** (z): replaces `6.0` in `(mouse.x - 0.5) * 6.0` → mapped to `mix(1.0, 10.0, z)`. Add **UV Warp Scale** (w): replaces `0.5` in `result_z * 0.5 + 0.5` → mapped to `mix(0.1, 1.0, w)`.

### `ascii-lens`
- **Missing:** z, w
- **Action:** Add **Glyph Line Width** (z): replaces `width = 0.1` → `mix(0.02, 0.25, z)`. Add **Brightness Threshold Bias** (w): global bias `-0.2` to `+0.2` applied to luma thresholds.

### `fabric-zipper`
- **Missing:** z, w
- **Action:** Add **Weave Frequency** (z): replaces `200.0` in `sin(uv * 200.0)` → `mix(50.0, 400.0, z)`. Add **Tooth Jaggedness** (w): replaces `tooth_amp = 0.02` → `mix(0.0, 0.1, w)`.

### `quad-mirror`
- **Missing:** z, w
- **Action:** Add **Rotation** (z): rotates the offset vector before `abs()` reflection, `mix(0.0, 6.283, z)`. Add **Mirror Sectors** (w): variable sector count replacing fixed 4-way mirror, `mix(2.0, 8.0, w)`.

### `bayer-dither-interactive`
- **Missing:** z, w
- **Action:** Add **Dither Spread** (z): scales Bayer threshold spread `mix(0.0, 2.0, z)`. Add **Pixel Scale Max** (w): replaces `mix(1.0, 16.0, mouse.y)` → `mix(4.0, 64.0, w)`.

### `neon-edges`
- **Missing:** z, w
- **Action:** Add **Layer Count** (z): replaces hardcoded loop `5` → `i32(mix(1.0, 10.0, z))`. Add **Flow Distortion** (w): replaces `0.015` noise warp multiplier → `mix(0.0, 0.05, w)`.

### `cyber-physical-portal`
- **Missing:** z, w
- **Action:** Add **Glow Sharpness** (z): replaces `exp(-abs(dist - radius) * 20.0)` → `mix(5.0, 50.0, z)`. Add **Grid Density** (w): replaces `fract(uv * 20.0)` → `mix(5.0, 50.0, w)`.

### `electric-contours`
- **Missing:** z, w
- **Action:** Add **Edge Threshold** (z): remaps `smoothstep(z * 0.5, (z * 0.5) + 0.3, edge)`. Add **Spark Speed** (w): replaces `t * 2.0` → `t * mix(0.0, 10.0, w)`.

### `chromatic-manifold`
- **Missing:** w
- **WGSL evidence:** `zoom_params.w` is already read for curvature on line 110 but not declared in JSON.
- **Action:** Add **Curvature Scale** (w) to JSON (range 0.0–2.0). Consider adding **Neighborhood Scale** as an `advanced_param` if supported.

### `engraving-stipple`
- **Missing:** w
- **WGSL evidence:** `zoom_params.w` is already read on line 51 for burr texture.
- **Action:** Add **Burr Texture** (w) to JSON (range 0.0–1.0).

### `perspective-tilt`
- **Missing:** w
- **Action:** Add **Plane Scale / Zoom** (w): scales `u_plane` and `v_plane` before UV remapping (range 0.5–2.0).

### `predator-camouflage`
- **Missing:** w
- **Action:** Add **Noise Scale** (w): replaces `noise(uv * 10.0)` multiplier → `mix(5.0, 40.0, w)`.

### `prismatic-mosaic`
- **Missing:** w
- **WGSL evidence:** `zoom_params.w` is already read on line 251 for fog density.
- **Action:** Add **Fog Density** (w) to JSON (range 0.0–1.0).

### `gen-isometric-city`
- **Missing:** w
- **Action:** Add **Building Height Scale** (w): replaces `8.0` in `pow(h_rnd, 2.0) * 8.0` → `mix(2.0, 16.0, w)`.

### `volumetric-cloud-nebula`
- **Missing:** w
- **Action:** Add **Extinction** (w): replaces `SIGMA_T_NEBULA = 1.2` → `mix(0.2, 3.0, w)`.

### `cyber-hex-armor`
- **Missing:** w
- **Action:** Add **Border Thickness** (w): replaces `border = 0.05` → `mix(0.01, 0.15, w)`.

### `directional-glitch`
- **Missing:** w
- **WGSL evidence:** `zoom_params.w` is already read on line 38 for angle bias.
- **Action:** Add **Angle Bias** (w) to JSON (range 0.0–1.0, mapped to 0–6.28 radians).

### `glass-bead-curtain`
- **Missing:** w
- **WGSL evidence:** `zoom_params.w` is already read on line 41 for glass density.
- **Action:** Add **Glass Density** (w) to JSON (range 0.0–1.0, mapped to 0.5–2.5 Beer-Lambert).

### `interactive-voronoi-lens`
- **Missing:** w
- **Action:** Add **Lens Curve** (w): replaces `sin(dist * 3.1415)` frequency → `mix(1.0, 10.0, w)`.

### `pixel-depth-sort`
- **Missing:** w
- **Action:** Add **Shadow Threshold** (w): replaces `0.05` in `luma < layer_height + 0.05` → `mix(0.0, 0.2, w)`.

### `radial-hex-lens`
- **Missing:** w
- **Action:** Add **Hex Edge Hardness** (w): replaces `0.45` ratio in smoothstep → `mix(0.3, 0.55, w)`.

### `rgb-delay-brush`
- **Missing:** w
- **Action:** Add **Alpha Absorption Scale** (w): replaces `5.0` in `mask * split * 5.0` → `mix(1.0, 10.0, w)`.

### `rgb-iso-lines`
- **Missing:** w
- **Action:** Add **Background Opacity** (w): replaces `0.1` multiplier on base image → `mix(0.0, 0.5, w)`.

### `sphere-projection`
- **Missing:** w
- **Action:** Add **Ambient Light** (w): replaces `ambient = 0.2` → `mix(0.0, 0.6, w)`.

### `x-ray-reveal`
- **Missing:** w
- **Action:** Add **Lens Edge Softness** (w): replaces `blur = 0.05` → `mix(0.0, 0.15, w)`.

### `cyber-terminal-ascii`
- **Missing:** w
- **Action:** Add **Decoder Radius** (w): replaces `decoder_radius = 0.15` → `mix(0.05, 0.4, w)`.

### `split-flap-display`
- **Missing:** w
- **Action:** Add **Damping** (w): replaces `velocity *= 0.92` → `mix(0.8, 0.99, w)`.

### `temporal-rgb-smear`
- **Missing:** w
- **Action:** Add **Mouse Influence Radius** (w): replaces `smoothstep(0.0, 0.3, dist)` → `mix(0.1, 0.6, w)`.

### `zipper-reveal`
- **Missing:** w
- **Action:** Add **Tooth Amplitude** (w): replaces `tooth_size * 0.5` → `mix(0.1, 1.0, w)`.

---

## Recommended Fix Order (Highest Impact First)

1. **Fix the 10 Critical JSON/WGSL mismatches first.** They are already coded to use params but users see no sliders.
2. **Fix the 5 High-priority 0-param generative shaders** by exposing the 4 params already wired in their WGSL.
3. **Fix the 9 Medium-priority 1-param shaders** next — adding 2–3 sliders each is straightforward.
4. **Finally, top off the 21 Low-priority 3-param shaders** with a single 4th slider.

---

## Full A-Z Search List (45 Shaders)

`ascii-lens`, `bayer-dither-interactive`, `chromatic-manifold`, `chroma-threads`, `complex-exponent-warp`, `cyber-hex-armor`, `cyber-physical-portal`, `cyber-terminal-ascii`, `digital-glitch`, `digital-haze`, `directional-glitch`, `electric-contours`, `engraving-stipple`, `fabric-zipper`, `gen-bioluminescent-aether-pulsar`, `gen-celestial-glass-tornado`, `gen-ethereal-quantum-medusa`, `gen-graviton-plasma-lotus`, `gen-isometric-city`, `gen-nebular-chrono-astrolabe`, `glass-bead-curtain`, `infinite-zoom`, `interactive-voronoi-lens`, `magnetic-ring`, `neon-edges`, `perspective-tilt`, `pixel-depth-sort`, `predator-camouflage`, `prismatic-mosaic`, `quantum-fractal`, `radial-hex-lens`, `rgb-delay-brush`, `rgb-iso-lines`, `scan-distort`, `spectral-mesh`, `spectral-rain`, `spectral-vortex`, `sphere-projection`, `split-flap-display`, `temporal-rgb-smear`, `volumetric-cloud-nebula`, `x-ray-reveal`, `zipper-reveal`

---

## Validation Checklist

After editing any JSON definition:
- [ ] Params count is exactly 4 (or fewer only if the WGSL genuinely ignores the remaining slots).
- [ ] Each param has `id`, `name`, `default`, `min`, `max`, and optional `step`.
- [ ] Param `id` is unique within the shader definition.
- [ ] Run `node scripts/generate_shader_lists.js` and verify no errors.
- [ ] No changes to `Renderer.ts`, `types.ts`, or bind groups.
