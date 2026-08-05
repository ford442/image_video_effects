# gen-3d-sierpinski-chaos — Optimizer pass (Batch 35, 2026-08-05)

192 → 242 lines (+50). Gate: ✅ naga OK, bindgroup compatible, 0 extraBuffer violations.

## Changes

**Contract repairs**
- Added the mandatory resolution bounds guard on `global_invocation_id`.
- History read switched from `textureSampleLevel(dataTextureC, u_sampler, …)`
  (filtering sampler + wrong centered-UV coords) to non-filtering
  `textureLoad(dataTextureC, pixel, 0)`.
- Depth was flat `0.0` → real generated depth: nearest contributing splat's
  projected Z mapped near-is-one (`clamp(1.0 - (nearestZ - 1.2) / 2.6, 0, 1)`),
  background stays 0.

**Performance**
- Hoisted the combined `rotY*rotX` matrix out of the chaos loop: was 4 trig +
  ~14 mul per sample, now 3 dot products per sample (2 trig total per pixel).
- Vertex picking switched from sin-based `hashf` to a 32-bit integer mix
  (no transcendental ops in the loop).
- Warmup/convergence loop folded into the main loop (`if (i < WARMUP) continue`).
- Saturation early-exit: once a pixel accumulates `count > 4.0` the loop breaks —
  dense core pixels exit in a fraction of the budget.
- Iteration budget 50–450 → 48–288 (+16 warmup) with a resolution LOD factor
  (`clamp(921600/(W*H), 0.5, 1)`); the temporal accumulator restores density
  over ~3–4 frames, so the visual stays dense at lower per-frame cost.
- Branch chain HSV→RGB replaced by a branchless cosine palette.

**Elegance / integration**
- Named constants (`CAMERA_DIST`, `BASE_ITERS`, `SATURATION_COUNT`,
  `HISTORY_DECAY`, `EXPOSURE`, `BG_COLOR`) replace magic numbers; sectioned comments.
- HDR-ready: exposure lift + treble shimmer can exceed 1.0 in rgba32float.
- Temporal: `dataTextureA` written every frame (history decay 0.96), presentation
  is the temporally accumulated color — the stochastic sampler visibly converges.
- Semantic alpha kept density-driven (0.35 bg floor → 0.95 saturated).
- Audio: canonical `plasmaBuffer[0].xyz` + guarded FFT bins 1–8 (arrayLength
  guard). Persistent smoothed bass in `extraBuffer[133]` with single-writer
  (`gid 0,0`) + length guard. Treble now actually drives the sample budget
  (the old `audioIntensity` was dead code).
- Click ripples (previously ignored entirely): bounded `min(rippleCount, 50u)`
  loop, 2.5 s finite lifetime, aspect-corrected expanding rings; rippleGlow
  drives hue drift, brightness flash, and a slight alpha lift — spatially local.

**Sliders (all LIVE, index order via `u.zoom_params`)**
1. Point Density → iteration budget (48 + density·240, treble-modulated)
2. Rotation Speed → orbit angular rate (bass-smoothed)
3. Point Size → splat radius (0.001–0.006 uv²)
4. Color Shift → palette phase (plus mids/FFT/ripple drift)

## Perf estimate
Worst case ~304 chaos iterations/pixel with ~15 flops each and early exit —
roughly 2× cheaper than the original 450-iteration trig-heavy loop, plus the
LOD scalar caps 1080p at budget×1.0 and 4K at ×0.5. Comfortable 60 fps at
1080p on mid-range GPUs.

## JSON
`updatedParams` verified byte-exact vs HEAD. Only additive `features` list added.
