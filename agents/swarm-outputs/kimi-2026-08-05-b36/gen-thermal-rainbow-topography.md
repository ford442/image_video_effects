# gen-thermal-rainbow-topography — Batch 36 upgrade (Algorithmist)

**Lines:** 199 → 289 (+90, within +50–90 budget)
**Gate:** `wgsl_precommit_gate.py` ✅ (naga OK, bindgroup compatible, 0 workgroup errors, 0 extraBuffer violations)

## What changed

### New algorithms (3 advanced, fused with the thermal-topography soul)
1. **Domain-warped FBM strata** (`terrainHeight` rework): a 2-octave FBM warp vector (canonically offset by `(5.2, 1.3)`) folds the two low-frequency terrain layers into geological ridges; the four micro layers stay unwarped and crisp → true macro+micro multi-scale structure. Warp amplitude is driven by the Terrain Scale slider (`warpAmt = 0.35 + scale·0.9`).
2. **Curl-noise flow** (`curlNoise2`): divergence-free 2D flow from finite differences of a time-drifting simplex potential (compute-safe, no `dpdx/dpdy`). The old plain-FBM flow lines are now advected by the curl field → coherent thermal currents instead of drifting fog.
3. **Worley micro thermal cells** (`worley2`, canonical `hash21`/`hash22`): F1 cellular noise at 6× terrain scale, riding the curl field, gated by `smoothstep(0.55, 0.95)` and driven by treble + the guarded FFT envelope — fine "thermal grain" beneath the macro contours.
4. **Thermal diffusion (simulation hint):** the height field is temporally diffused against last frame's height stored in `dataTextureA.a` (`mix(hRaw, prevHeight, clamp(0.55 − speed·0.35, …))`) — a discrete heat-equation step that doubles as frame-to-frame temporal coherence; Evolution Speed slider controls the diffusion rate.

### Contract compliance repairs
- **Added resolution bounds guard** (was missing).
- **dataTextureA now written EVERY frame** (was never written): `rgb` = tonemapped feedback-smoothed display history, `a` = diffused height field. The existing `dataTextureC` read now yields this shader's own coherent history.
- **Semantic alpha fix:** old alpha multiplied by raw source depth (could vanish on generative/empty input). New alpha = `clamp(luma·0.55 + contourDensity·0.6) · mix(1, depth, 0.2)` — depth is a bounded modulator, never a kill switch.
- **Guarded FFT bins 1–8** (indices 6..13, `arrayLength` guard, clamped) → `fftEnv` driving Worley cell glow. No fake spectrum.
- **Click ripples:** bounded loop `min(u32(max(u.config.y,0)),50u)`; expanding heat rings `exp(-|r − age·0.3|·14) · exp(-age·1.4)`, capped at 1.5, added to the height field + warm color contribution. Finite, spatially local.
- **Audio now uses all three bands:** bass (terrain scale/CA, existing), mids (contour glow pulse), treble (Worley cell shimmer).

### Bug fix (noted deviation)
- **Mouse mapping was broken:** old code computed `mouseUV = (mousePos.x / res.x − 0.5)·aspect` — but `mousePos` is already 0–1 uv, so the hotspot was pinned near the top-left corner regardless of cursor. Fixed to `(mousePos.x − 0.5)·aspect` in centered aspect space (y=0 top preserved, no flip). The "mouse-interactive" feature is now truthful.

### Slider wiring (all 4 live, index order preserved via `u.zoom_params.xyzw`)
- p1 Intensity → glow/specular/contour/Worley energy
- p2 Evolution Speed → time factor + thermal diffusion rate (new second role)
- p3 Terrain Scale → terrain zoom + domain-warp fold amplitude (new second role)
- p4 Color Shift → thermal palette offset (contours + cells)

### JSON
Additive only: `description` extended, `features` populated (15 truthful entries). `updatedParams` verified byte-exact vs HEAD (sorted-key diff identical). Removed dead code (`mod289_3f`, `taylorInvSqrt4` — unused) to stay in line budget.

## Perf estimate
terrainHeight went from 18 to ~22 snoise evals (warp adds 4) and is called 5× per sampleTerrain ×3 chromatic samples + 1 depth recompute ≈ 350 snoise/pixel (+~15%). Curl adds 5 snoise, Worley 9 cell hashes per sampleTerrain call. Early-outs: none cheaply available (height field is full-screen), but all loops are compile-time bounded. Estimated ~45–60 fps at 1080p on a mid-range discrete GPU; simplex FBM is the sole hotspot.

## Deviations
- Mouse-mapping bug fix described above (behavior change, but makes the declared mouse-interactive feature actually work; click effects remain guarded, finite, spatially local).
