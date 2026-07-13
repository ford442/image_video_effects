# Optimizer upgrade — `gen-volcanic-ink`

## Changelog

| Area | Change |
|------|--------|
| **Performance** | Added resolution-aware LOD scaling (3–6 fBM octaves). |
| **Performance** | Replaced the per-frame point-sampled feedback with an unrolled 3×3 bilinear neighbor blur. |
| **Performance** | Reused a single domain-warp offset for fissure and lava layers; reduced redundant fBM calls. |
| **Elegance** | Named constants for palette, helperized warp/LOD/tone/chromatic functions, logical section comments. |
| **Pipeline** | Writes persistent trails to `dataTextureA` and feature masks (lava, cracks, ember, smoke) to `dataTextureB`. |
| **Pipeline** | Reads `readDepthTexture` and blends a subtle amount into the generated depth buffer. |
| **Quality** | Switched ember sparks from white-noise grid thresholds to blue-noise jittered cells with twinkle. |
| **Quality** | Added compute-safe chromatic aberration and required ACES tone mapping. |
| **HDR** | Keeps lava/spark values >1.0 in linear space before ACES; writes `rgba32float`. |

## Techniques used (≥2 from toolkit)

1. **LOD scaling** — `qualityLOD()` chooses 3–6 octaves from `min(width,height)` plus the user detail slider (`p4`), staying inside a 1080p frame budget.
2. **Blue-noise sampling** — ember sparks are placed with `hash22`-jittered grid cells instead of raw `hash21` thresholds.
3. **Bilinear LOD / unrolled kernel** — the temporal trail uses nine explicit `textureSampleLevel` taps on `dataTextureC` with a fixed 3×3 kernel.
4. **Reduced branching** — `select()`-based LOD, `step()`/`smoothstep()` masks, and `mix()` blends replace most per-pixel branches.
5. **Uniform-based tuning** — all four UI params feed named, remapped uniforms; no magic numbers in the hot path.
6. **Slot chaining hints** — `dataTextureA` carries the persistent ink trail, `dataTextureB` exports a feature mask for downstream shaders.

## Performance estimate

- **Loop / step budget** — worst case ≈ 6 octaves × 3 fBMs + 3-octave smoke ≈ 21 value-noise evaluations ≈ 84 hash calls, well under the 300-step limit.
- **Texture samples** — 9 bilinear taps for temporal blur + 1 depth load per pixel.
- **Target** — 60fps at 1080p on a mid-tier GPU; detail drops to 3 octaves automatically on smaller canvases.

## Slot recommendations

| Slot | Usage |
|------|-------|
| `writeTexture` | Final RGBA `rgba32float` output (ACES tone mapped, semantic alpha). |
| `writeDepthTexture` | Generated depth blended 15% with `readDepthTexture`. |
| `dataTextureA` | Persistent ink trail for next-frame feedback. |
| `dataTextureB` | Feature mask `.rgba = (lava, cracks, emberSpark, smoke)` for downstream compositing. |
| `dataTextureC` | Read as the previous frame during temporal blur. |
| `readDepthTexture` | Optional depth-aware alpha/depth blend. |

## Validation notes

- Uses the exact 13-binding canonical header from `WGSL_BUILTINS_GENERATIVE.md` §0.
- Entry point: `@compute @workgroup_size(16, 16, 1)`.
- Bounds guard uses `global_id` / `pixel` vs `res`.
- Compute-safe functions only: `textureSampleLevel`, `textureLoad`, `textureStore`; no `tan`, `textureSample`, `dpdx`, or `dpdy`.
- Semantic alpha: derived from presence/intensity, not hardcoded `1.0`.
