# BRIEFS — fork A (tone-histogram, tone-histogram-apply)

Written before any WGSL edit. Baselines snapshotted to `<scratch>/a/*_head.wgsl` (post-prelude-migration, pixel-identical to origin/main).

## HEAD findings (verified by reading + rendering HEAD, SwiftShader, SRC=img / SRCFLAT)

**tone-histogram-apply (Pass 2) is an orphan that cannot work.**
- Reads `extraBuffer[1]` (total), `[2]` (peak bin), `[3..258]` (256 bins). `grep` over `public/shaders/` and `src/` finds **no writer** of that range. `tone-histogram` was rewritten as a single-pass v2 (only its binding mentions `extraBuffer`); `multipassRegistry.ts` has no pass-1 entry for it; the only pass-1 that ever wrote bins (git `4ff9722e`) wrote `atomic<u32>` counts that this shader reads as `f32` (denormals ≈ 0), and `extraBuffer[0..132]` is re-uploaded every frame — so the pair never worked chained.
- Render HEAD, image-like source: exposure pinned at 3.5, contrast ×~63, output near-binary posterised (meanL 0.742, stdL 0.387, see `apply_head_def.png`); flat source: pure black (`meanL 0`, `apply_head_flat.png`). The harness `extra` buffer is only 256 floats, so bins 253..258 are also OOB reads.
- Even with a correct histogram HEAD would under-expose: exposure targets the mean, then Reinhard `c/(1+c)` maps 0.5 → 0.33 (output mean sags to ~0.26–0.39 of target), and `255/tonalSpan` goes up to ×63 on a flat frame (span clamped only at 4).
- Hardcoded alpha `1.0`.

**tone-histogram (v2).**
- `uv = gid / res` samples texel **corners** (half-texel up-left): every tap is a 2×2 bilinear blend, so the whole picture is box-blurred and the 3×3 "local stats" are not texel-exact.
- "Haze Removal" **adds** haze: `mix(color, hazeColor(0.75,0.78,0.82), (1-depth)*haze*0.3)` washes far pixels toward a grey-blue as the slider rises. Opposite of the name/description. (Default slider is 0, so the default look is unaffected.)
- Grain is flat (same ±0.02 amplitude on clear base, midtones and dense shadow).

---

## SHADER: tone-histogram  (second pass)
IDENTITY: single-pass local adaptive histogram-equalisation-style tone grade — local mean/std stretch about a spot-meter-biased reference, film toe + per-channel dye shoulder, split-tone, grain, depth haze control, ACES. A colourist still reads it as "auto local tone / film curve".
KEEP VERBATIM: 4 params and roles (Stretch Amount → targetStd + chroma gain + bass bias; Toe; Shoulder; Haze Removal); 3×3 `localStats`; mouse spot meter (`meterWeight = 0.35 + 0.25·down`, `stretchRef = mix(localMean, meterLuma, w)`); `adaptGain` clamp 0.5..2.5; `filmCurve`; per-channel shoulder ×1.08/1.0/0.92; split-tone constants; held-pointer exposure zone; `g1/g2` hash grain base and its mids modulation; ACES on display; `tonalConfidence·localContrast·depth` alpha; `A = outColor` (display RGBA; C is unread, so this is truthful). Existing `Ideas:` entries (mouse local metering window; per-channel shoulder) untouched.

MECHANISM INTERROGATION
- Tactic 1 (deepen the kernel): the 3×3 stats window measures texel-scale noise, not a tonal *neighbourhood*. Local adaptive equalisation's defining term is the **regional brightness**, which a 9-tap texel window cannot see. Next-better approximation of the same operator: add a coarse, range-weighted (edge-aware) regional mean.
- Tactic 2 (physics one step further): the file is explicitly "film-like"; real print grain is a function of density (Selwyn: σ ∝ √(D(1−D))) — peaks in midtones, vanishes in clear base and dense shadow. HEAD grain is flat.
- Tactic 3 (promote an intermediate): `curvedLuma` (post film curve) and `localMean` are already computed and thrown away after the split-tone; they feed both ideas.
- Tactic 6 (history): C is not read and HEAD does not need history; none added (no packing change).

ADD (2 native ideas):
1. **Density-weighted grain** (§12.2A) — `σ(L)=√(L(1−L))·2` from `curvedLuma` scales the EXISTING `g1/g2`; midtones keep today's amplitude, base and blacks go quiet (`mix(0.25, 1, density)`). Native: the file already has grain and a film curve.
2. **Wallis local-brightness pull with an edge-aware coarse mean** (§12.2A, A2) — 4 bilinear taps at ±3.5 texels, range-weighted `1/(1+(Δl/0.12)²)` so the mean never averages across a real edge; the Wallis target mean becomes `stretchRef + (0.5 − μ_coarse)·0.5·Stretch Amount`, i.e. dark regions lift and bright regions settle as Stretch Amount rises (0 → HEAD). The std-normalisation half of Wallis already exists (`adaptGain`); this is the missing mean half that makes it *adaptive equalisation* rather than a local contrast knob.
FORMULA ADMISSION: both rows are in the photographic table; #1 consumes `curvedLuma`, #2 consumes `localMean/localStd` + 4 extra loads (A2: "otherwise 4 extra loads"); deletion test: remove either → still exactly this effect; keep only either → not this effect. Row use: density-weighted grain + Wallis here; CLAHE-clip is used on the apply file only (not here).
RESCUES (loud): R1 half-texel sampling → `uv = (gid+0.5)/res` (picture is sharper than HEAD; 3×3 stats now texel-exact). R2 Haze Removal now removes haze (Koschmieder inversion `J=(I−A·h)/(1−h)`, same `(1−depth)·slider·0.3` weight, same airlight colour) instead of adding it; slider 0 is unchanged.
FORBID: springs, ripples, IQ palette, halation (not a tone-curve beat), new params, anything that replaces `filmCurve`.
A PACKING: ACES display RGBA (unchanged).

---

## SHADER: tone-histogram-apply  (first pass; orphan Pass 2 rescue)
IDENTITY: histogram-driven auto-grade — measure the frame's luma histogram, auto-expose to a target mean, stretch by the p05..p95 span, scale saturation, and (mode) hue-shift when the histogram's peak sits at an extreme. A colourist reads it as "auto-exposure / auto-levels".
KEEP VERBATIM: 4 params and roles (Target Luma → `targetLum = mix(0.35,0.65,x)`; Contrast → `mix(0.85,1.55,y)·(255/span)`; Saturation → `mix(0.80,1.55,z)`; Dynamic Hue Mode ≥0.5 → hue shift `0.08·sin(t·0.9 + peakBin·0.05)` when `peakBin<40 || >215`); `exposure = clamp(targetLum/meanLuma, 0.5, 3.5)`; weighted-mean / p05 / p95 / peak-bin reduction over 256 bins; Reinhard curve family; pivot-0.5 contrast; HSV saturation; depth passthrough; A packing **(exposure/3.5, meanLuma, peakBinNorm, saturation) — raw stats, never ACES** (HEAD-consistent, documented in header). multipass `prevShader` JSON key and registry entry left as they are (coordinator-owned contracts).

RESCUE R1 (the histogram input): self-contained histogram. `var<workgroup> wgHist: array<atomic<u32>,256>`; all 256 invocations cooperate (zero → barrier → each takes 4 samples of a fixed 32×32 stratified grid with static hash jitter over the **whole frame** → `atomicAdd` → barrier); thread 0 then runs the SAME reduction as HEAD (weighted mean, p05/p95, argmax peak). Every workgroup computes the identical histogram (integer counts, order-independent), so there are no tile seams and no frame-to-frame shimmer on static content. No `extraBuffer` access remains.
RESCUE R2: contrast gain `255/tonalSpan` capped at ×3 (HEAD allowed ×63 on a flat frame — a flat field has no histogram to stretch).
RESCUE R3: alpha `1.0` → `src.a` (coverage passes through a chain).

MECHANISM INTERROGATION
- Tactic 1 (deepen the kernel): the histogram is read only as summary scalars (mean, two percentiles, one argmax). The next-better use of the *same* histogram is its cumulative distribution — the classic equalisation operator — made contrast-limited so it cannot amplify a spike bin (CLAHE clip).
- Tactic 2 (physics one step further): Reinhard `c/(1+c)` maps scene 1.0 → 0.5, so an "expose to target mean" tool under-delivers its target. The photographic fix is the extended Reinhard with a white point `W`: `c·(1+c/W²)/(1+c)`; the histogram already measures where the highlights end (p95).
- Tactic 3 (promote an intermediate): `p05/p95` are computed and only their *difference* is used; the cumulative sum the loop already accumulates is the CDF. Both ideas come straight out of the existing reduction loop.
- Tactic 6 (history): A already stores the stats (write-only today). An AE adaptation lag through C was considered and **rejected**: C can hold another shader's A after a shader swap and there is no trustworthy sentinel; not worth a misfire.

ADD (2 native ideas):
1. **Clip-limited CDF equalisation blend** (§12.2A CLAHE-style clip) — clip each bin at 3× the mean bin count, redistribute the excess uniformly, build the CDF in the same thread-0 pass (`wgCdf[256]`), then remap the graded luma toward `cdf(srcLuma)` hue-preservingly (`ratio=(Lt+0.01)/(Lg+0.01)`, clamped). Amount rides the existing Contrast slider (`0.5·y`; y=0 ⇒ HEAD behaviour).
2. **Percentile-anchored white point** (§12.2A, histogram-native) — Reinhard stays Reinhard but becomes the extended form with `W = max(p95/255·exposure, 0.6)`: the measured 95th percentile lands at white, the tail above it rolls off; mid-tones no longer sag.
FORMULA ADMISSION: both consume quantities the file already computes (the bin loop's cumulative sum and p95); no new state/binding/spring; deletion test: either removed → still the auto-grade; either kept alone → not a different shader. CLAHE-clip is used only here in the batch's fork A.
FORBID: springs, ripples, IQ palette, ACES (Reinhard is this file's tone curve; adding ACES would double-tone-map and would be hygiene, not an idea), extraBuffer state, new params, a second histogram pass.
A PACKING: raw stats field `(exposure/3.5, meanLuma, peakBinNorm, saturation)` — unchanged, never tone-mapped; C is unread.
Features tags: no `upgraded-rgba` (no ACES, per §8); header gets `Upgraded:`, `Ideas:`, `A packing:`. Tags `audio-reactive`/`mouse-driven` are NOT claimed (neither is used).

---

## Amendments after implementation (cards above are unchanged; these are the deviations)

1. **Correction to HEAD finding.** My first "flat source → pure black" HEAD render omitted `SRC=img`, i.e. it was an *empty* texture, not a flat one. Re-run properly: HEAD apply on a flat 0.5 source → **pure white** (`meanL 1`); on the three photo-like scenes → blown white / black / white (`apply_head_*.png`). Conclusion unchanged: HEAD Pass 2 is non-functional.
2. **tone-histogram-apply Idea 2 evolved** (found by slider sweep, not by reading): (a) with the white point at p95 and HEAD's source-span contrast about a fixed 0.5, highlights and shadows double-counted and clipped; so the span is now measured **after** the tone curve and the stretch pivots on the **tone-mapped mean** with **soft-rolled tails** (`softEnds`) instead of the hard clamp. (b) Pivoting on the percentile midpoint made **Target Luma inert**; pinning the mean to Target Luma lifted an **all-black frame to grey (0.376)**. Final: anchor = `mix(meanT, targetLum, reach)`, `reach = min(a,1/a)`, `a = mean·exposure/target` (how far the 0.5…3.5 exposure clamp can really deliver). Result: Target Luma moves the output mean 0.45→0.55 (land), 0.38→0.56 (hazy), 0.39→0.49 (dim); black frame stays 0.026; flat 0.5 stays 0.489.
3. **tone-histogram: third rescue.** HEAD's `select(gain, 1.0, localStd < 0.001)` is a hard switch — on 8-bit gradient bands, band interiors (std 0) get gain 1 while band edges (std ≥ 0.001) jump to the ×2.5 clamp → dashed banding, and flat sky got the *most* boost. Now `mix(1, gain, smoothstep(0.002, 0.03, localStd))`. (Found by ablation: dashes were present with only the half-texel fix, i.e. HEAD behaviour exposed, not caused by my ideas.)
4. **Wallis pull coefficient** tuned 0.5 → 0.3 · Stretch Amount (0.5 lifted black trees to speckled grey).
5. **CDF built in the same thread-0 loop** as the reduction (spread applied analytically at lookup) — one 256-iteration serial pass fewer; output bit-identical (max diff 0).
6. File-local numbering: `tone-histogram` already has `Idea 1/2` comments (spot meter, dye shoulder) from the 2026-09-09 pass, so the new ones are `Idea 3` (grain) and `Idea 4` (Wallis) in the WGSL — card ideas 1/2 above.
