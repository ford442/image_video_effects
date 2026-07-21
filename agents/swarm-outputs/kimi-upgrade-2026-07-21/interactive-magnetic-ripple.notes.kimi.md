# Upgrade Notes — interactive-magnetic-ripple (Algorithmist, 2026-07-21)

## Line-count delta
- Original: 223 lines → Upgraded: 302 lines (**+79**, within the +50…+90 target band; brief target 273–313 ✅)

## Changes by domain

### Worley field-line distortion layer (new)
- Added `worley(p, t)` cellular noise (F1/F2 distances, 3×3 cell scan, slow sin/cos cell jitter) — ~24 lines.
- The F2−F1 ridge field acts as magnetic "domain walls": it computes a per-pixel bend angle `(ridge − 0.35) * PI * pLineMix` and rotates the mouse-relative sampling vector via a new `rot2()` helper before ripple phase/frequency evaluation, so straight ripples curve along field lines.
- Blend is exactly `mix(dAspect, rotated, pLineMix)` — default slider 0.3 matches the brief's "mixed at ~0.3, param-controlled".
- The same ridge term also twists the `atan2` field-line angle term (`+ ridge * 4.0 * pLineMix`) and boosts crest mask on high-ridge field lines.

### Spring-damped ripple envelope (new, replaces plain linear/exp decay)
- Added `springEnvelope(x, zeta, omega)`: classic under-damped oscillator impulse response `exp(−ζωx)·(cos(ω_d x) + (ζω/ω_d)·sin(ω_d x))` — starts at 1.0 (same as old `exp(−dist·decay)`), then overshoots below zero, rings, and settles.
- Mouse ripple attenuation now `springEnvelope(sampDist, dampZeta, springOmega)` with `dampZeta = 0.12 + pSpring·0.78`, `springOmega = 2.5 + freq·0.35`.
- Stored 50-ripple-point loop: age decay `exp(−rAge·1.2)` replaced by `springEnvelope(rAge·0.6, dampZeta, 4.0 + freq·0.1) * exp(−rDist·decay)` (spatial falloff kept, time decay is now springy).

### Treble sparkle on crests (new)
- `crestMask` accumulates `smoothstep(0.72, 0.98, ripple·rippleAtten)` (mouse wave maxima), field-line ridge crests, and stored-ripple crests (`smoothstep(0.75, 1.0, rRipple)`).
- Crest sparkle = `sparkle(offset UV, time·1.3, treble) · crest · sparkGain`, tinted slightly blue-white `(0.85, 0.95, 1.2)·0.7`, added after the ambient sparkle overlay. Highlights appear only at wave maxima; driven by `plasmaBuffer[0].z`.
- Crest also contributes +0.1 to semantic alpha so sparkle peaks read in compositing.

### Slider params (exactly 4, zoom_params.x/y/z/w, JSON index 0–3)
- **x / index 0 — Ripple Frequency** (default 0.5): unchanged semantics (`pFreq·40·(0.8+env·0.4)`).
- **y / index 1 — Field-Line Mix** (default 0.3): NEW — worley bend amount (re-scoped from old "Ripple Decay"; decay behavior now lives inside Spring Damping).
- **z / index 2 — Spring Damping** (default 0.5): NEW — damping ratio ζ of the spring envelope plus spatial `decay = 0.5 + pSpring·3.0` (formula preserved from the old y-param, so decay feel carries over).
- **w / index 3 — Treble Sparkle** (default 0.3): NEW — `sparkGain = 0.3 + pSparkle·1.6` scaling both ambient and crest sparkle.
- Demoted to fixed constants (defaults preserved visually): `fieldStrength = 0.55·bassPulse` (was slider 3 at 0.5), `chromaticSplit = 0.04` (identical to old default 0.5×0.08).
- Legacy `params` array in JSON kept untouched for backward compatibility; `updatedParams` added per brief with `updated: true`.

### Preserved / untouched
- Canonical 13-binding layout verbatim, no binding 13 (shader never used historyTexture).
- `@workgroup_size(16, 16, 1)`, bounds guard, all three sampler reads use `textureSampleLevel(..., 0.0)`.
- Writes `writeTexture`, `writeDepthTexture`, `dataTextureA` every frame (same payload layout: env, mSmooth.xy, rippleIntensity — downstream consumers unaffected).
- Core algorithm intact: bass envelope + spring-smoothed mouse, magnetic pull with velocity boost, curl-noise advection, mids-morph field lines, click-burst shockwave, 50-point ripple accumulation, FBM domain warp, chromatic split sampling, hue-cycled glow, temporal trail, ACES, depth fog, semantic alpha.

## QA flags
- **No-GPU caveat**: validated with naga + bindgroup gate only; the Cloud VM has no WebGPU adapter, so visual/perf behavior (spring ringing intensity, worley bend feel, crest sparkle thresholds) is NOT eyeballed on real hardware.
- **Eyeballed constants** (may need tuning after visual pass): worley scale 5.0 & ridge offset 0.35, spring `dampZeta` range 0.12–0.90 and `springOmega = 2.5 + freq·0.35`, crest smoothstep edges (0.72–0.98 / 0.75–1.0), crest sparkle tint weights (0.85/0.95/1.2)·0.7, fixed `fieldStrength 0.55` and `chromaticSplit 0.04`.
- **Slider re-scope note**: indices 1–3 changed meaning per the brief (Decay→Field-Line Mix, Field Strength→Spring Damping, Chromatic Split→Treble Sparkle). Saved user presets for old sliders will map to the new semantics; defaults were chosen so out-of-box look stays close to the original.
- Spring envelope can briefly go negative (intended overshoot); `rippleIntensity` uses `abs()` so intensity never subtracts.
- Worley jitter uses `sin/cos(t·0.7 + h·TAU)` — bounded, no TDR risk; 9-cell loop is cheap relative to existing fbm/curl cost.
