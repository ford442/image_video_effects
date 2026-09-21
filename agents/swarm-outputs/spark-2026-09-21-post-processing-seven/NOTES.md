# Post-Processing Seven — Implementation Notes

**Agent:** spark · **Date:** 2026-09-21 · Cards: [`BRIEFS.md`](BRIEFS.md) · +312 / −76 across seven files.

## Photo tools

### `pp-sharpen` (+25 / −1)
- **Kept:** all params; 8-tap bilateral blur; coring; all three modes; spring lens; ripple surge; C anti-jitter.
- **Idea 1 — anti-halo clamp:** `minLuma` / `maxLuma` tracked in the existing kernel loop (no new taps);
  sharpened luma clamped to `[min − haloRoom, max + haloRoom]`, `haloRoom = 0.015 + amount·0.03`.
- **Idea 2 — luma-only:** result rebuilt as `centerCol + (clampedLuma − centerLuma)`.
- **Scope:** both ideas are inside `if (mode < 0.66)`. **Mode 2 (the neon one) is byte-for-byte HEAD.**
  It is the contract's §7 bad example, but removing it would break presets that select it; not this
  batch's call.

### `pp-vignette` (+25 / −3)
- **Kept:** all params; grade chain; both blend branches; triangular grain generator; spring; ripples; C.
- **Idea 1 — cos⁴:** `cosFocal = 1.12 / effectiveFalloff`, `cos4 = 1/(1 + (r/f)²)²`, blended 55 % into
  `vigMask`. Everything downstream of `vigMask` (feedback, alpha, depth) follows it.
- **Idea 2 — emulsion grain:** `grainResponse` midtone curve; grain added to `graded` *before* the blend
  modes, and removed from the final `hdr` sum.

### `pp-chromatic` (+53 / −5)
- **Kept:** all params; `lensWarp`; five-band Cauchy sampling and reconstruction weights; click lens;
  spectral caustic; history mix.
- **Idea 1 — longitudinal CA:** `defocusDisc()` helper; `focusDepth` sampled under the lens `center`
  (which already follows the pointer); signed `defocus`; G softened on one side of focus, R+B on the
  other. Radius `|defocus|·(0.002 + chroma·0.35)` — rides the chroma slider.
- **Idea 2 — purple fringing:** 6-tap ring at `fringeReach` looking for near-clipped values; violet added
  only where this pixel is the darker side. Amount `0.08 + chroma_slider·0.7`.
- The depth load moved up (`depthHere`) and is reused for the depth write.
- **JSON:** `upgraded-rgba` appended (ACES present, ideas landed).

## Temporal (history ring)

### Floor fix in all four — history-ring depth
`histDepth = max(textureNumLayers(historyTexture), 1u)`; layers wrap by it; every age clamped to
`histDepth − 1`. On an 8-layer device the layer arithmetic is identical to HEAD. `HISTORY_DEPTH` constants
removed from all four files (grep is clean).

### `temporal-slit-scan` (+49 / −14)
- **Kept:** all params; tent pivot; tears; spectral jitter; alpha; A packing.
- **Idea 1:** `frameAt()` / `frameAtAge()` — fractional age blends neighbouring layers.
- **Idea 2:** `shutter` width `(0.35 + spread·0.9)·smoothstep(0,1,age)`; 1-2-1 box over three ages.
- Full spread now reaches the oldest layer the ring actually holds (`reach = min(7, histDepth−1)`), so a
  4-layer device gets the whole ramp with fewer distinct frames, not a ramp clipped at column 3/7.

### `optical-flow-tracer` (+63 / −27)
- **Kept:** all params; LK normal equations; warped-history trail; raw flow packing in A.
- `lucasKanade()` grew `stride`, `half`, `prior` and now returns `vec3(flow, λmin)`. With
  `stride=1, half=2, prior=0` it is HEAD's solve.
- **Idea 1 — Shi–Tomasi:** `lambdaMin` from the same tensor sums; final flow × `smoothstep(0.0005, 0.01, λmin)`.
- **Idea 2 — pyramidal:** coarse solve (`stride 4, half 1`) → confidence-gated, clamped ±8 px prior →
  fine solve on the pre-warped previous frame.
- **Cost:** ~204 texture fetches/pixel vs HEAD's 150.
- 1-layer ring: flow 0 and the trail falls back to the live frame instead of blending toward black.

### `temporal-frequency-decomposition` (+46 / −18)
- **Kept:** all params; lens spring; pings; band voices; alpha; A packing.
- **Idea 1 — Hann window:** per-sample `w = 0.5 − 0.5·cos(2π(t+½)/N)`; magnitude normalised by `Σw`;
  pings scaled by `Σw/N` so their brightness matches HEAD.
- **Considered and rejected:** subtracting the mean before the DFT. It is standard spectral practice, but
  it would make a still photograph stop glowing at every frequency. That is a different look, not a
  deeper one. With Hann alone, stills still glow at low frequency (main lobe) and glow ~3× less at
  ≥ ~0.25 cycles/frame, where the unwindowed sidelobe was pure leakage. **Visible change on stills.**
- **Idea 2 — phase → hue:** luma-weighted `atan2(imag, real)`, up to ±¼ turn around the user's hue,
  faded by `smoothstep(0.01, 0.06, energy)`.

### `spatio-temporal-3d-conv` (+51 / −8)
- **Kept:** all params; both 3×3 helpers; per-mode temporal weights and composites.
- **Idea 1 — motion-adaptive weights:** `similarity = exp(−|Δrgb|²/(2·0.07²))`, applied only when
  `mode < 0.33`. **Card corrected during implementation** (NR only, not NR + sharpen) — see BRIEFS.
- **Idea 2 — variance-driven NR:** similarity-weighted luma moments → `noiseSigma` →
  `nrGain = mix(0.35, 1, smoothstep(0.004, 0.03, σ))`, multiplied into NR strength.
- `accumW ≈ 0` now falls back to `current` (HEAD mixed toward black; similarity can legitimately zero it).

## Not done — flagged

1. **The other 7 history-ring shaders still have the depth bug:** chrono-luma-slit-scan,
   temporal-rgb-ghost, temporal-feedback-zoom-tracer, temporal-phosphor-burn,
   temporal-phosphor-burn-motion-adaptive, temporal-decay-multiresolution,
   temporal-layered-time-stamps. The fix is mechanical (the `frameAt`/`ringLayer` pattern here) and
   worth one small hygiene PR — kept out of this batch so the ideas diff stays reviewable.
2. **The four temporal files carry `upgraded-rgba` but have no ACES.** Pre-existing metadata drift.
   Adding ACES to a pass-through of a display-referred photo would just dim it; left alone.
3. **pp-sharpen mode 2** is still the contract's own "reject" example. Left, for preset compatibility.

## Gates

| Gate | Result |
|---|---|
| precommit `--files` (7) | 7 passed, 0 workgroup, 0 extraBuffer |
| naga `--all` | 1380 valid, 40 known, **0 new** |
| extraBuffer / dead-sliders | PASS / PASS (**7 scanned**, all four sliders read in all 7) |
| catalog-counts / wgsl-include | passed / green |
| Jest | 712 / 6 — same four pre-existing WASM-bridge suites |
| `SKIP_WASM_BUILD=1 npm run build` | compiled successfully |
| `shader_definitions/` | one line: `upgraded-rgba` on pp-chromatic |

Real-GPU visual QA: not done. The history-ring fix in particular can only be *seen* on a device that
lands on the 4-layer fallback.
