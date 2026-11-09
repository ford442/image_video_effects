# NOTES — Fork B (prismatic-feedback-loop, gen-prismatic-mobius-helix, prismatic-3d-compositor)

Harness: SwiftShader WebGPU, rgba32float, static photo source. Structural/PNG evidence only — **no real-GPU visual QA claimed.** Gates (all three): Naga (naga-wasm) valid; `wgsl_precommit_gate.py` pass; `audit_dead_sliders.py` PASS (4/4 sliders live each).

## prismatic-feedback-loop
- **Kept verbatim:** 4 params/roles, accumulativeAlpha raw accumulation (ACCUM_RATE .5), rot2 drift, depth attenuation, held warp, click bursts, glow = trailLum², ACES on display, alpha, depth.
- **A packing:** raw accumulated RGBA (C read as colour+alpha); texel (0,0) = (glide.xy, 7, fract(time)), masked to zero on every C read (`loadHist`, incl. echo taps).
- **Idea 1 prism echo** (`// ── Idea 1`, `histBilinear` + `echoK = 0.3·feedbackMix`): history re-read through the R/B taps, exact 4-tap bilinear loads; Feedback 0 stays HEAD's freeze (harness: 0.000 both before/after, history starts zero). **Idea 2 Cauchy weights** (§12.2F, `cauchyScale(0.2)` → R×0.887, B×1.197) on live taps, click kicks and echo.
- **Rescue R1:** dead extraBuffer spring → first-order glide in A(0,0) (rate 10); `springVel = (raw − glide)·10`.
- **Look (default params 0.5,1,.8,.02, 60 fr, 192/576):** meanL 0.4642→0.4665, stdL 0.2224→0.2214 (192). Visible: smoother, slightly softer trails (bilinear echo) with compounding fringes. 60→200 frames stable (0.4650→0.4660; params 0.9,3,1.5,0.2 + audio 200 fr: 0.470; nan 0 everywhere, held mouse + ripple + audio 0.8,0.5,0.9).
- Formula rows: Cauchy dispersion (F). Open: the glide/spring is first-order, not critically damped; JSON `spring-interaction` feature dropped (description text still says "sprung" — not touched, outside features/tags/x-meta).

## gen-prismatic-mobius-helix
- **Kept verbatim:** 4 params, sdMobius / mobiusHelixInfo, edge/surface glow, thinFilm palette + hue, helix trail, traveler, seam current, C blend, ACES, alpha, depth. A = ACES display RGBA (unchanged).
- **Idea 1 film-thickness fringes** (§12.2F thin-film phase): `across` added to `MobiusInfo`; δ=4π·1.33·d·cosθ/λ, d = 420 + 360·across + 45·ring + 120·treble nm; cos²(δ/2) per channel × palette `film` (mean gain ≈1). **Idea 2 SDF-gradient bevel** (§12.2E): 4 distance-only evals (`mobiusDistance`), screen-space gradient, key light (−0.6,−0.8); lip = edge·max(lit,0)², far-side edge dimmed.
- **Rescue R-phase:** traveler `time·(0.07+bass·.015)` → `time·0.07`, bass widens the packet; seam wave `time·(3+mids)` → `time·3`, mids in spatial frequency.
- **Look (0.55,.45,.5,.6, 576, 60 fr, no audio):** meanL 0.0838→0.0849, stdL 0.0929→0.0974; ribbons now show interference banding and a lit lip. nan 0 (audio/held/ripple renders too).
- Open: slice shows small rectangular sections, hatching reads strongly at 576 px; fringe frequency may want a real-GPU look.

## prismatic-3d-compositor
- **Kept verbatim:** 4 params, parallax + in-bounds mask, 5×5 glow gather + prismTint, aberration/flare law, 0.5 videoBlend, 0.85−mids·.25 feedback, alpha, depth.
- **A packing:** trail colour (smoothed display RGB) + composite-luminance alpha; C read as colour.
- **Idea 1 afterglow:** the write-only trail is shown: `max(prev − finalColor,0)·(0.45+0.4(1−depth))` added to output. **Idea 2 cursor light shafts:** 4 taps (step 0.07, decay 0.7) toward the pointer with the glow's own threshold·exp(−depth) weight, × prismTint × 0.22·glowIntensity.
- **Rescue:** `textureSampleLevel(dataTextureC, non_filtering_sampler…)` → exact `textureLoad`.
- **No ACES (deliberate):** input is Pass-1 display colour; a tone-map or hue-preserving clip dulled the clouds in renders (tried, reverted: meanL 0.57→0.50). JSON `upgraded-rgba` dropped (no ACES in WGSL).
- **Look (1,1,1,.02, 60 fr, mouse .3,.6):** meanL 0.5744→0.5941, stdL 0.3123→0.3248 (192) — the shafts. Afterglow is zero on a static source (harness cannot show motion; expected behaviour prev≈finalColor); needs a real-GPU/moving-source look. nan 0 (held, audio, ripple, params 10,4,4,.2 × 200 fr).
