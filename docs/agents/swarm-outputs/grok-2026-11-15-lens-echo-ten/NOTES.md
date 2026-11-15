# Notes — grok/lens-echo-ten (2026-11-15)

Second pass on the ten smallest shaders (108–121 lines). Each file kept its kernel, modes, and saved params. Two ideas were added in the existing main path. `temporal-halation-freeze` and `pp-tone-map` were migrated to `#include "_prelude.wgsl"` first; that swap is not an idea.

Real-GPU visual QA: external. This VM has no hardware GPU.

## Per shader

### tilt-shift
- Kept: Scheimpflug band, 16-tap golden-angle gather, hex weight, center specular add, OOF chromatic split, HSV saturation, blur vignette. Params: Blur Amount, Focus Width, Saturation, Tilt Angle.
- Idea 3 in the gather: cat's-eye clip of outward taps, gated by off-axis distance and coc.
- Idea 4 in the gather: Airy-shaped weight (§12.2F) on bright taps only. Diffuse taps keep the hex.
- A packing: ACES display RGBA.

### hyb-temporal-fbm-ghost
- Kept: domain warp, three rotating channel offsets, per-channel same-pixel C lag, source-tied halo, effect mix. Params: Temporal Shift, FBM Scale, Warp Amount, Effect Mix.
- Idea 3: exact C load at `coord - round(disp * res)`, mixed by temporal shift.
- Idea 4: halo gain follows `|disp| / warpAmt`.
- A packing: ACES display RGBA. C is that display.

### chroma-threads
- Kept: horizontal thread id, pluck, anisotropic weave, sheen BRDF, SSS, RGB split. Params: Thread Density, Vibration Amp, RGB Split, Decay.
- Idea 1: weft at half density, checkerboard duck of mask and live offset.
- Idea 2: `C.r` damped by Decay and added to the offset. Higher Decay still means a shorter ring.
- A packing: telemetry `(offset, influence, sheen, alpha)`. ACES on writeTexture only. `x-meta.upgrade.params` added; saved `params` unchanged.

### concentric-spin
- Kept: lagged center, rose/epi from mids, alternating spin, tangent conveyor, gap bloom, click pulse. Params: Density, Speed, Smooth W, Gap Fade.
- Idea 3: `pitch = smoothW * (0.35 + 1.8 * r)`. Zero Smooth W still closes every gap.
- Idea 4: shoulder band of `edge`, lit by `cos(a - rot)`.
- A packing: `lag.xy` telemetry plus alpha. ACES on writeTexture only.

### temporal-halation-freeze
- Kept: 7-tap hex bloom, dye-layer lag, held freeze, color temp, ghost, envelope in A.a. Params: Exposure Length, Decay Rate, Bloom Color Temp, Ghost Echo.
- Idea 3: outer hex taps mix toward red × luma. Center tap stays source color.
- Idea 4: source pulled toward luma by `length(newHalo)` before the bloom add.
- A packing: raw accumulated halo RGB + envelope. ACES on writeTexture only.
- Prelude migration this pass (header only, not the upgrade).

### alpha-luminance-history
- Kept: advected history, 4-neighbour diffusion, mouse paint, ripple flash, history-tint multiply. Params: Memory Decay, Glow Intensity, History Tint, Trail Diffusion.
- Idea 1: rising luma uses `min(decay * 2.4 + 0.08, 0.9)`; falling luma uses `decay * 0.42`.
- Idea 2: glow tint mixes the warm lamp with `C.rgb`.
- A packing: raw state. A.rgb = current source, A.a = rolling luminance. ACES on writeTexture only. `upgraded-rgba` added to features.

### chrono-luma-slit-scan
- Kept: `frameAt` ring clamp, luma→age, runner window, isochrones on raw `ageFrac`, ripple warp, held spread shrink. Params: Temporal Spread, Warp Strength, Luma Gamma, Original Blend.
- Idea 3: two extra `frameAt` taps along `(slitBandV, slitBandH)`, mixed in by spread.
- Idea 4: frame mix weight is `0.5 - 0.5 * cos(ageFrac * π)`.
- A packing: display RGBA. History is binding 13.

### video-echo-chamber
- Kept: aspect-correct orbit, chromatic streak, click rings, motion key and its floor, depth decay. Params: Global Decay, Mouse Radius, Echo Strength, Color Shift.
- Idea 3: `echoColor` pulled toward luma by `motionMemory` before the blend, so it is in the stored echo.
- Idea 4: 4-neighbour luma edge of the source, times `motionNow`, added after the A store.
- A packing: pre-ACES echo RGB + motion memory. ACES on writeTexture only.

### alpha-hdr-bloom-chain
- Kept: 16-ring gather, threshold, hover halo, click fronts, history mix cap, saturation. Params: Bloom Radius, Bloom Intensity, Exposure, Saturation.
- Idea 1: Cauchy `n(λ) = 1 + 0.0045/λ²` sets the red/blue ratio. Green offset stays 0.19. Directions stay opposite.
- Idea 2: `taken = min(max(spread, 0) * 0.35, sourceHdr)`, then `sourceHdr - taken + spread`.
- A packing: raw HDR RGB + overexposure. ACES on writeTexture only. `upgraded-rgba` added to features.

### pp-tone-map
- Kept: four curves, continuous mix on `algorithm * 3`, hue-preserving contrast, saturation toward luma, bass on exposure, no second ACES, input is `readTexture`. Params: Algorithm, Exposure, Contrast, Saturation.
- Idea 3: when exposure is negative, shadows take `safe * (1+k) / (safe+k)`. At exposure ≥ 0 the curves see the linear scale.
- Idea 4: after saturation, a shoulder toward luma for peaks above ~0.78, then clamp.
- A packing: display RGBA, already tone-mapped.
- Prelude migration this pass (header only, not the upgrade).

## Formula ledger

| Shader | §12.2 rows |
|---|---|
| tilt-shift | Airy (§12.2F) |
| alpha-hdr-bloom-chain | Cauchy (§12.2F), energy-conserving bloom (§12.2F) |
| temporal-halation-freeze | halation red fringe (§12.2A), core bleach (§12.2A) |
| pp-tone-map | H&D toe (§12.2A) |
| the other six | no §12.2 row; ideas are local to the existing kernel |

No row is shared across files.

## Closeout

## 2026-11-15 — lens-echo ten (10 shaders)

- IDs: tilt-shift, hyb-temporal-fbm-ghost, chroma-threads, concentric-spin, temporal-halation-freeze, alpha-luminance-history, chrono-luma-slit-scan, video-echo-chamber, alpha-hdr-bloom-chain, pp-tone-map
- Per shader, the ideas actually added:
  - tilt-shift: cat's-eye aperture clip; Airy ring on defocus specular. Hex gather and center bloom kept.
  - hyb-temporal-fbm-ghost: upstream C sample along the warp; crest-scaled halo. Per-channel lag kept.
  - chroma-threads: weft duck; pluck ring-down from C.r. Decay still shortens the trail.
  - concentric-spin: radius-opened grooves; shoulder glint facing the spin. Lag packing kept.
  - temporal-halation-freeze: red outer hex taps; core bleach. Dye lag and freeze hold kept.
  - alpha-luminance-history: fast attack / slow release; glow hue from stored RGB. A stays raw state.
  - chrono-luma-slit-scan: slit-travel smear; raised-cosine shutter. Isochrones still use raw ageFrac.
  - video-echo-chamber: echo chroma collapse; display-only motion rim. Motion key kept.
  - alpha-hdr-bloom-chain: Cauchy tap ratio; energy taken from the source before the add. HDR packing kept.
  - pp-tone-map: underexposure toe; hue-stable highlight shoulder. Four curves kept. No second ACES.
- Floor: prelude include on all ten (two migrated this pass), 16×16, exact C or `frameAt`, A packing as above, saved params exact.
- Gates: Naga 10/10, precommit bindgroup 10/10, extraBuffer 0, dead sliders 0, `npm run verify:shaders:fix` 11/11, `npm run build` succeeded. Schema tests pass alone. The full Vitest run hit 50 timeouts under load (UI and numpy specs, not these shaders).
- Real-GPU visual QA: external. Thumbnails for these ten are stale until a GPU machine refreshes them.
