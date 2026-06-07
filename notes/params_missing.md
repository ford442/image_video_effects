# Shaders Missing Custom Uniform Params — RESOLVED

> **Status: ALL FIXED** (last updated 2026-04-17)
>
> The Pixelocity renderer exposes **4 float sliders** via `zoom_params` (`x`, `y`, `z`, `w`). All previously broken or missing param mappings have been repaired across **44 shader definitions** and their corresponding WGSL sources.

---

## Summary of Fixes

| Severity | Original Count | Status |
|----------|----------------|--------|
| 🔴 Critical | 10 | ✅ Fixed — WGSL read undeclared slots; JSONs now expose all 4 params |
| 🟠 High | 5 | ✅ Fixed — 0-param shaders now have full param sets |
| 🟡 Medium | 24 | ✅ Fixed — 1–2 param shaders completed to 4 params |
| 🟢 Low | 6 | ✅ Fixed — 3-param shaders topped off with 4th params |

**Total affected:** 44 shaders (~6.2% of all 709 definitions)

---

## What Was Done

1. **Removed non-functioning `zoom`, `x`, `y` param references** from WGSL where they were broken.
2. **Added proper `mapping` fields** to every shader JSON so each slider maps unambiguously to `zoom_params.x/y/z/w`.
3. **Converted `sliders` arrays** (generative placeholder schema) to standard `params` arrays.
4. **Wired unused `zoom_params.z/w` slots** in WGSL for shaders that previously only used x/y.
5. **Fixed copy-paste errors** (`neon-edges.wgsl` was an exact duplicate of `prismatic-mosaic.wgsl`; both JSONs now match the actual WGSL behavior).
6. **Re-routed miswired uniforms** (e.g. `chromatic-manifold` had `tearThreshold` reading from `zoom_config.x` which is Time — now correctly reads `zoom_params.z`).

---

## Notable Individual Fixes

| Shader | Fix |
|--------|-----|
| `quantum-fractal` | Added Scale (x), Iterations (y), Entanglement (z); Edge Glow (w) already existed but was shadowed by a local variable — now uses `u.zoom_params.w` |
| `infinite-zoom` | Added Zoom Speed (x), Distortion (y), Rotation (z), Max Iterations (w) |
| `spectral-vortex` | Added Twist Scale (x), Distortion Step (y), Color Shift (z); replaced hardcoded curl amp with `zoom_params.w` |
| `chroma-threads` | Replaced generic `zoom_params` placeholder with Thread Density (x), Vibration Amp (y), RGB Split (z), Decay (w) |
| `spectral-mesh` | Replaced generic `zoom_params` placeholder with Grid Density (x), Displacement (y), Mouse Radius (z), Color Shift (w) |
| `scan-distort` | Replaced generic `zoom_params` placeholder with Block Size (x), Quantization (y), MV Visibility (z), Glitch Frequency (w) |
| `chromatic-manifold` | Added Color Boost (x), mapped Warp Strength (y), fixed Tear Threshold to use `zoom_params.z`, mapped Curvature (w) |
| `engraving-stipple` | Mapped Density (x), Ink Threshold (y), Mouse Light (z), added Burr Texture (w) |
| `directional-glitch` | Mapped Intensity (x), Radius (y), Scatter (z), added Angle Bias (w) |
| `glass-bead-curtain` | Mapped Bead Size (x), Refraction (y), Tension (z), added Glass Density (w) |
| `digital-glitch` | Replaced 3 unmapped params with Corruption Intensity (x), Bit Manipulation (y), Error Propagation (z), Decay Rate (w) |
| `electric-contours` | WGSL declared `zoom_params` but never used it — now fully wired to x/y/z/w |
| `neon-edges` / `prismatic-mosaic` | Both JSONs updated to match the shared compiled WGSL which reads x/y as layer speeds and w as fog density |

---

## Generative Placeholders Converted

These generative shaders previously used non-standard `sliders` arrays. They now use standard `params` with `mapping`:

- `gen-celestial-glass-tornado`
- `gen-ethereal-quantum-medusa`
- `gen-graviton-plasma-lotus`
- `gen-nebular-chrono-astrolabe`
- `gen-bioluminescent-aether-pulsar`

---

## Validation

- `node scripts/generate_shader_lists.js` — ✅ **PASSED**
- `node scripts/check_duplicates.js` — ✅ **PASSED** (709 unique IDs)

---

## Remaining Action Items

None. All known `zoom_params` mismatches are resolved. If new shaders are added in the future, ensure every JSON param includes:

```json
{
  "id": "unique_name",
  "name": "Display Name",
  "default": 0.5,
  "min": 0.0,
  "max": 1.0,
  "step": 0.01,
  "mapping": "zoom_params.x",
  "description": "What it controls"
}
```
