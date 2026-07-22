# generative-psy-swirls — Visualist Upgrade Notes (Kimi, 2026-07-22)

**Role:** Visualist
**Shader:** `public/shaders/generative-psy-swirls.wgsl`
**Brief:** `swarm-tasks/kimi-generative-briefs-2026-07-22/generative-psy-swirls.md`

## Key Changes

- **fbm domain warp before twist:** added canonical `valueNoise` + `fbm` helpers (canonical constants) and a 3-octave 2D warp field applied to `p` before the polar twist. Swirl arms now bend and breathe instead of rotating rigidly. Warp scale derives from the `frequency` slider; warp drift speed picks up a treble shimmer.
- **Mids-driven chromatic hue fan:** `layeredSwirlLayer` gained a `hueShift` parameter. Per-layer hue stagger `fi * mids * 0.06` plus a global mids offset (`±0.10` on R/B channels) fans layers into rainbow fringes on musical peaks (plasmaBuffer[0].y), per brief.
- **Temporal feedback clamp (luma-echo-warp lesson):** the memory write to `dataTextureA` is now a dedicated trail path — clamped pre-tint at 1.2, gently tinted toward blue (`0.98/0.99/1.02`), then hard-limited to 1.2 again post-tint. Accumulated color can no longer blow up across frames. Display color still blends the (unclamped) previous frame as before.
- **Slider rewiring (ids/defaults untouched, saved-preset contract kept):**
  - `zoom_params.x` (Twist Amount) → vortex twist strength, bass-kicked (unchanged semantics, still real).
  - `zoom_params.y` (Layer Count) → 2–7 stacked swirl layers.
  - `zoom_params.z` (Frequency) → now drives BOTH the polar arm frequency AND the domain-warp field scale/strength, so the slider visibly reshapes the warp character.
  - `zoom_params.w` (Depth Reduction) → depth-based twist flattening (unchanged semantics).
- Canonical 13-binding layout preserved verbatim; `@workgroup_size(16, 16, 1)`; writes to `writeTexture`, `writeDepthTexture`, and `dataTextureA` every frame; `textureSampleLevel(..., 0.0)` for sampler reads; no reserved-keyword identifiers; no binding 13 (shader doesn't use historyTexture).
- JSON: added `updatedParams` (index 0–3) and `"updated": true` exactly per the brief's block. No other fields changed.

## Line Count Delta

- Before: 129 lines
- After: 189 lines
- Delta: +60 (target +50 to +90 ✅; brief range 179–219 ✅)

## Gate Result

- `python3 scripts/wgsl_precommit_gate.py --files public/shaders/generative-psy-swirls.wgsl` → exit 0, naga OK, bindgroup compatible, 0 warnings.

## QA Flags / To Verify on Real GPU

- **No GPU in this VM** — naga validation + bindgroup check only; visual QA deferred to a real-GPU run.
- **Eyeballed constants** (need visual tuning pass):
  - `warpStrength = 0.10 + freqParam * 0.10 + bass * 0.03` — warp amplitude may be too subtle/too wobbly at extremes.
  - `warpScale = 1.5 + freq * 1.5` — warp field density vs. swirl frequency coupling.
  - Hue fan gains: `fi * mids * 0.06` per-layer stagger and `±0.10` R/B mids offsets — fringe spread on peaks.
  - Trail tint `(0.98, 0.99, 1.02)` and double 1.2 clamp — confirm no visible banding in long trails and no residual runaway on strobing mids.
- Loop bound `i32(layers)` maxes at 7 layers × 3 channel calls with 6 fbm evaluations per pixel per frame outside the loop — should be fine, but watch frame time at 4K on weaker GPUs.
