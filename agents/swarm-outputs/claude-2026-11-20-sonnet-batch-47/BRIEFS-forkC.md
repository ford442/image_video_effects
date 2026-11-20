# BRIEFS — fork C (spec-temporal-path-tracer, gen-chrono-erosion-feedback-melting)

Written BEFORE any WGSL edit beyond the coordinator's header-only `_prelude` migration. HEAD = `git show origin/main:public/shaders/<id>.wgsl`; HEAD baselines rendered (SwiftShader, `SRC=img`, 192 px) and looked at first.

HEAD findings (rescues, verified):
- **chrono-erosion**: (a) `uv = id.xy / res` (no +0.5) feeds BOTH the live sample and the history sample → every frame the feedback is read half a texel up-left and bilinear-blurred → a global diagonal drift + 2×2 blur in the loop. The HEAD render shows exactly this: diagonal streak grid, no crisp detail. (b) history read with the filtering `u_sampler` on `dataTextureC` (rgba32float) — contract says exact `textureLoad`. (c) the "sprung smudge" lives in `extraBuffer[133..138]`; `writeExtraBuffer` re-uploads the whole 256-float scratch every frame (`src/renderer/webgpu/audioDepth.ts:56`), so `extraBuffer[137]` is always 0 → the spring re-initialises to the raw cursor every frame: **dead spring**, behaviour == raw cursor. (d) per-band FFT turbulence reads `plasmaBuffer[1..8].x`, but only `plasmaBuffer[0]` is uploaded (`audioDepth.ts:62-70`) → `bandEnergy` is always 0: **dead audio**. The live FFT is `extraBuffer[5..132]`. (e) alpha hard-coded 1.0, no ACES on display.
- **path tracer**: (a) accumulation hard-resets to 1 spp when `sampleCount > 300` → a full-frame pop to raw noise every 300 frames; (b) the running mean never forgets, so a video/webcam source ghosts for 300 frames after any change (and the held-pointer light barely shows: weight 1/300 per frame); (c) the header says "blue-noise jittered" but the angle is a white-noise hash. No zero-C early return, no negative into ACES (radiance ≥ 0), A is raw (rgb mean, a = n) and read back as such — consistent.

---

## 1. spec-temporal-path-tracer  (FIRST PASS)

```
SHADER: spec-temporal-path-tracer
IDENTITY: 2D Monte-Carlo path tracer over the photo — each pixel marches a ray to the nearest
  luminance edge, bounces (roughness-jittered reflect, Russian roulette), gathers colour
  bleed, and the result is a running mean in C; ACES on display.
KEEP VERBATIM: 4 params + roles (bounces→2..5, edge_threshold→0.05..0.3, radiance→0.5..2.0,
  roughness→0..1); marchToEdge (32 steps × 2 texel); edgeStrength/edgeNormal; reflect +
  roughness jitter; Russian roulette; sky pickup 0.3; mouse-held 30 % pull of the ray toward
  the cursor; raw-accumulation A (rgb = mean radiance, HDR, never ACES'd); ACES on writeTexture
  only; depth pass-through; hash22/hash11.
ADD (3 native ideas):
  1. Low-discrepancy ray angle — θ = 2π·fract(cp(pixel) + idx·φ⁻¹) (R1 sequence with a
     per-pixel Cranley–Patterson rotation) replaces the white hash angle the header calls
     "blue-noise". Successive frames cover the circle evenly, so the per-pixel angular
     integral converges ~O(1/N) instead of O(1/√N): the first second is visibly cleaner.
  2. Hit-distance falloff — the marcher already finds the hit distance and throws it away.
     Gathered radiance now falls off as a soft 2D inverse-distance law with a core radius
     (§12.2F "soft inverse-square", 2D exponent), normalised at the mean hit distance so
     exposure is kept and clamped so contact hits can't blow out: colour bleed becomes
     local (a bright edge next to you lights you, one 60 px away barely does).
  3. History that can forget — C.a is the sample count; its fraction now carries a 5-tap
     (centre + 4 diagonals) source-luma fingerprint. If the fingerprint of the live source
     moves, the kept sample count shrinks (TAA-style disocclusion / history rejection) so a
     changing video re-converges instead of ghosting; the periodic 300-frame hard reset is
     replaced by a bounded exponential horizon (N≤300), and while the pointer light is held
     the horizon shortens to 32 so the moving light is actually visible.
MECHANISM INTERROGATION:
  tactic 1 (kernel): the operator is a Monte-Carlo estimate of the angular integral of
    incoming radiance. HEAD's estimator is i.i.d. white-noise angles. Next-better estimator of the
    SAME integral = quasi-random (R1 + per-pixel rotation). Same kernel, same marcher.
  tactic 2 (physics one step): real transport attenuates with path length; HEAD weights a hit
    at 2 px and at 64 px identically, so "colour bleeding" (the description's promise) is not
    local. 2D radiometry falls ∝ 1/d.
  tactic 3 (promote an intermediate): `hit.pos − pos` (distance) and `sampleCount` are computed
    and unused / used only for a reset. Distance → falloff; count → forgetting.
  tactic 6 (history): C is a raw field (mean, count). One more piece of continuity without
    changing the packing contract for the first three channels: the fraction of `a`.
FORMULA ADMISSION (§12.4):
  - R1 / Cranley–Patterson (tactic 1, QMC: algorithmist "Halton/low-discrepancy" family) —
    same-noun: Monte-Carlo path tracer; operates on the ray angle it already draws; deletion
    test both ways OK (without it: same picture, noisier; without the tracer: nothing).
  - §12.2F soft inverse-square — this shader is a light-transport effect (lighting family);
    consumes the hit distance marchToEdge already computes; additive scalar on the existing
    gather.
  - TAA history rejection / bounded EMA (fork-C claimed row) — consumes C it already reads.
  No spring / ripple / IQ palette / new binding / new param.
FORBID: springs, ripples, IQ palettes, replacing the edge marcher, touching the roughness
  mapping, new params, any frame-hash strobing.
A PACKING: raw accumulation (HDR, not ACES'd). A.rgb = mean radiance; A.a = n + 0.9·fp where
  n = integer sample count (≤300) and fp = 5-tap source-luma fingerprint ∈ [0,1]. HEAD: a = n.
  C is read by this file only, as exactly that. Display RGBA to writeTexture (ACES, alpha =
  source coverage ∪ convergence). dataTextureB untouched. (Documented in header + NOTES.)
```

## 2. gen-chrono-erosion-feedback-melting  (FIRST PASS)

```
SHADER: gen-chrono-erosion-feedback-melting
IDENTITY: video melting along a curl-noise vector field — decaying feedback history is dragged
  through the flow, the cursor smudges it, clicks stir vortices, bass shocks it, a per-band
  FFT boils strips of it.
KEEP VERBATIM: 4 params + roles (decay→0.05..0.95 weight, flowIntensity→0.005..0.055,
  turbulence→×(1+bandEnergy), feedbackMix→scales decay: meltW = decay·(feedbackMix/0.6));
  curlNoise (eps 0.01, uv·3, t·0.1) + value noise; smudge cursor push, click-vortex loop (2 s,
  exp(−1.8 age)); bass>0.6 shock; displaced-UV feedback blend `mix(current, feedback, meltW)`;
  flow-magnitude colour shift; beat inversion >0.7; 1.5 HDR clamp; A = colour history.
ADD (2 native ideas):
  1. Sharper melt advection — history is now resampled with a 16-load Catmull-Rom filter
     (`_std_sample` `catmullRomWeights`/`loadClamped`, copied verbatim) limited to the min/max
     of the 4 inner corners (no ringing). §12.2D goal ("sharper advection, no extra solver"):
     bilinear advection through a feedback loop is a repeated 2×2 blur, so melt streaks smear
     to mush; cubic + limiter keeps edges in the streak. (Also the rescue of the filtering
     sampler on rgba32float.)
  2. Macroblock motion carry — §12.2B datamosh: real moshed video drags whole macroblocks by ONE
     motion vector. Stateless version: the curl vector is also evaluated at the 16×16-px block
     centre, and where the field is strong (|curl| high) the pixel's vector is pulled toward
     the block vector (≤ 0.75), so fast streams tear into rigid blocks while calm regions
     stay liquid. Mouse / vortex / shock terms stay per-pixel so the cursor smudge is not blocky.
MECHANISM INTERROGATION:
  tactic 1 (kernel): the kernel is semi-Lagrangian resampling of the history. Bilinear = 2nd
    order, diffusive every frame (the loop applies it N times). Next-better approximation of
    the same operator: cubic Catmull-Rom + limiter.
  tactic 2 (physics one step): "Datamosh-like" (the file's own description). The first-order
    artefact of the real thing is block-constant motion vectors (P-frames), not per-pixel flow.
  tactic 3 (promote an intermediate): `length(curl)` and the 4 bilinear corners are computed/implied
    and thrown away → block-carry weight, limiter bounds.
  tactic 6 (history): C is read as colour history; exact 16 loads give the neighbourhood
    bounds for free. No packing change.
FORMULA ADMISSION: §12.2D (sharper advection, one-pass Catmull-Rom form) — consumes the
  displaced history the file already reads; §12.2B macroblock motion carry — datamosh-only row,
  this file is explicitly datamosh-like; operates on the flow field it already computes.
  Deletion test both ways OK: remove the blocks → still a curl melt; remove the cubic → same
  melt, blurrier.
FORBID: replacing the curl melt with a pure block mosh, a new spring / ripple system, chroma
  delay line (fork A's row), IQ palettes, new params.
RESCUES (default look changes — flagged): half-texel uv bias (+0.5) → exact feedback loop,
  no diagonal drift; filtering sampler → exact loads; dead spring → pinned to the raw cursor
  (behaviour identical, dead state removed); dead plasmaBuffer[1..8] band energy → live
  extraBuffer FFT bins (octave bins 2^b−1); ACES on display (A keeps the HDR history);
  alpha = source coverage ∪ melt energy (data-moshing convention).
A PACKING: display-colour history (HDR ≤1.5, pre-ACES) in A.rgb as at HEAD; A.a = 1.0 (C.a
  unread, as at HEAD). ACES applied on writeTexture only.
```

---

## AMENDMENT (after measuring on SwiftShader; the cards above were the plan, these are what shipped)

Two ideas on the cards failed measurement and were replaced **before** being kept — recorded here so a reviewer can see why the final cards differ.

**spec-temporal-path-tracer — Idea 1 changed.** Planned: low-discrepancy (R1 → R2) ray angle with Cranley–Patterson rotation. Measured (192 px, SRC=img, HEAD vs new, same frames): high-frequency noise 0.0170 (HEAD) vs 0.0180 (new) at 60 frames, error vs a 280-frame reference no better — the integrand has edges everywhere plus white-noise RR/roughness dimensions, so QMC on one dimension buys nothing. **But** the QMC render exposed concentric rings on every disc, and the 280-frame HEAD render has the same rings: they are the marcher's 2-px step quantisation baked into the *converged* image (HEAD's white-noise speckle only hides them early). Shipped Idea 1 = **stratified march lattice**: the step lattice is offset per sample by a jitter in [0,1) (`marchToEdge(..., lattice)`, lattice = 0 ≡ HEAD). Verified: the 280-frame converged image has no rings. Angle sampling reverts to HEAD's white noise (seeded by sampleCount + floor(time·60) because sampleCount now clamps at the horizon).
  Also tuned on the VM: falloff clamp [0.45, 1.25], FALL_R0 = 12 px, FALL_REF = 26 px (mean luma 0.196 vs HEAD 0.198 on SRC=img; +18 % on the very edge-dense SRC=tex); fingerprint ramp smoothstep(0.025, 0.10).

**gen-chrono-erosion-feedback-melting — Idea 1 changed.** Planned: 16-load Catmull-Rom history resample with a min/max limiter (§12.2D). Measured: Laplacian-std retention vs HEAD 0.048 — exact bilinear 0.097 (the rescue alone doubles detail retention), 8-load axis-cubic 0.107, full cubic 0.120 — but cost 1.67–2.3× HEAD (axis-cubic 1.4–1.57×) against the ≤1.3× cap (HEAD is ~8–11 ms at 256² on SwiftShader; the cubic's 16 loads dominate). Trimmed per COMMON.md: history is read with `_std_sample` `loadBilinear` (4 exact loads, verbatim) and the cubic idea is replaced by **flow-lane persistence** (§12.1 tactic 4, second-order Trail Decay): the curl magnitude the file already computes marks the lanes that stream; there `meltW *= (1 + 0.35·lane)` (lane = smoothstep(0.3, 0.9, |curl|)), so trails run longer along the flow lanes while calm regions keep HEAD's weight; scaled by the weight so Feedback Mix = 0 is still live-only. Idea 2 (macroblock motion carry) unchanged.
