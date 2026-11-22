# BRIEFS — fork D (tone-histogram, tone-histogram-apply), sonnet/batch-53

Both files were upgraded yesterday (sonnet/batch-48, e140179c) — this is a **3rd pass**. Written BEFORE any WGSL edit. Baselines: `scratchpad/d/tone-histogram_head.wgsl`, `tone-histogram-apply_head.wgsl` (+ `_prelude.wgsl`). Renders: 256 px, SRC=img (synthetic photo + synthetic depth), JSON defaults, audio 0.3,0.2,0.1.

## Pair relationship (checked)
**Independent now.** `tone-histogram-apply` builds its histogram in-pass from `readTexture` only (batch-48 rescue); it reads nothing tone-histogram writes (no `dataTextureC` / `extraBuffer` reads; `tone-histogram` is single-pass v2 and C-unread). The only coupling left is metadata: apply's JSON has `multipass:{pass:2,totalPasses:2,prevShader:"tone-histogram"}` and `multipassRegistry.ts` has an entry for apply (pass 2) but none for tone-histogram — registry/JSON are coordinator-owned, left alone. Chained after tone-histogram, apply would grade an already-ACES'd frame (double tone-map) — "Works standalone or after tone-histogram" is the existing description.

## Failure checklist (user's list) on both files
| check | tone-histogram | tone-histogram-apply |
|---|---|---|
| ACES on display RGB, non-negative input | ACES, input `max(color,0)` ✓ | **No ACES by design**: extended Reinhard + `softEnds` *is* its tone curve (ACES on top = double tone-map; batch-48 decision, `pp-sharpen`-style precedent). Input `src.rgb ≥ 0`, `softEnds` handles the negative side (tanh-clamped). Not changed. |
| audio via `plasmaBuffer[0].xyz` | bass → targetStd, mids → grain ✓ (JSON claims audio-reactive, true; treble unused) | not claimed, not present ✓ |
| `dataTextureC` / A | A = ACES display RGBA, C unread ⇒ truthful | A = raw stats field `(exposure/3.5, meanLuma, peakBinNorm, saturation)`, C unread ⇒ A write is dead data but documented; kept |
| extraBuffer | none ✓ | none ✓ |
| other (pow-neg, ripple.w, dead masks, half-texel, hardcoded alpha) | alpha semantic ✓, uv texel-centre ✓ | alpha = `src.a` ✓ |
| JSON claims | audio-reactive / mouse-driven / depth-aware / upgraded-rgba all true | features/tags true; `multi-pass-2` is now a registry artefact (flag) |

No writes to extraBuffer anywhere in the pair; the user's "extraBuffer 0 / 10" failure does not occur here.

## HEAD defects found (verified by varying inputs on HEAD)
1. **tone-histogram: Shoulder Strength is effectively dead.** shoulder 0 → 1 at defaults: **max 2/255, 0.0 % of pixels > 2/255** (toe 0 → 1 for comparison: 16 % px, max 11/255). Cause: `filmCurve` shoulder lifts highlights toward 1 by ≤ 0.3·(1−x) above 0.75 and ACES then flattens it; it also *lifts* where a shoulder (and Idea 2's own comment, "dye rolloff") should *roll off*. Flagged by batch-48 fork A, left unfixed there. → addressed by Idea 5 below (rescue + idea).
2. **tone-histogram-apply: the Saturation stage and the Dynamic Hue Mode spend light the equaliser accounted for.** HSV saturation/hue scaling is at constant V (= max channel), so Rec.709 luma moves. Saturation 0 → 0.5 → 1 at defaults: **meanL 0.518 → 0.481 → 0.445** (a 14 % brightness swing on a grade whose job is to hold Target Luma); local luma shifts up to ±0.15 (38/255); hue mode on: local luma shifts up to 0.23 (60/255). → Idea 3 below.

## tone-histogram — Idea Card
```
SHADER: tone-histogram
IDENTITY: single-pass local adaptive histogram stretch with a film toe/shoulder, split tone, grain and depth haze removal
KEEP VERBATIM: 4 params/roles (Stretch, Toe, Shoulder, Haze), 3×3 localStats, spot meter + meterWeight, adaptGain clamp 0.5..2.5 and its smoothstep gate,
  coarseMean Wallis pull, toe half of filmCurve, per-channel dye shoulder ×1.08/1/0.92, split tone, density-weighted grain, held-pointer exposure zone,
  Koschmieder haze inversion, ACES, alpha formula, every existing Ideas: item
ADD:
  5. H&D exponential shoulder knee (§12.2A, row "H&D characteristic curve") — filmCurve's shoulder becomes the real upper knee of a film curve:
     above knee k = 1 − 0.5·Shoulder the signal is rolled off y = k + (1−k)(1−exp(−(x−k)/(1−k))) (value- and slope-continuous). Shoulder 0 ⇒ k = 1 ⇒ HEAD identity.
     Consumes: curvedLuma and the three dye-channel curves (already computed). Also the rescue for the dead Shoulder slider.
  6. Chroma follows the tone curve (hue-preserving ratio) — HEAD adds mix(chroma, dyeChroma) to the *curved* luma, so where the stretch/curve lifts a shadow ×2 the colour
     difference stays put (washed shadows) and where the shoulder compresses a highlight it stays too (neon highlights). Scale the colour difference by
     clamp((curvedLuma+0.02)/(luma+0.02), 0.6, 1.8), weighted by Stretch Amount (0 ⇒ HEAD). Consumes: luma, curvedLuma, chroma, dyeChroma.
FORBID: halation / bloom blur, extra taps, springs/ripples, IQ palettes, replacing the 3×3 Wallis kernel, touching the toe half of the curve
A PACKING: ACES display RGBA (unchanged; C unread)
```
**§12.1 interrogation.** (1) Kernel: `filmCurve` approximates an H&D characteristic curve; the next-better approximation of its *shoulder* is the exponential knee (the HEAD form is a lift, not a roll-off). (2) Physics: a film shoulder compresses highlights *and* the dye layers lose saturation as they approach the shoulder (energy accounting: a compressed channel carries less colour difference). (3) Promoted intermediates: `curvedLuma/luma` is computed implicitly and thrown away — it is the local tone gain, exactly what the colour difference must follow. (6) History: none owned (C unread) — not used.
**§12.4 admission (H&D row, Idea 5):** family match — row is in table A and the file's own nouns are toe/shoulder/film curve; operates on what exists — curvedLuma + dye curves, no new tap/state; deletion test — delete the idea ⇒ HEAD curve (same effect); keep only the idea without the stretch/Wallis/grain/haze ⇒ a bare tone curve, not a tone histogram. Idea 6 is not a table row (domain-native, no ownership needed): same-noun — tone curve + saturation; deletion test passes both ways. **Open call to flag:** Idea 5 flips the shoulder's direction (lift → roll-off) and so slightly dims highlights at the default 0.5 for saved presets with Shoulder > 0.

## tone-histogram-apply — Idea Card
```
SHADER: tone-histogram-apply
IDENTITY: histogram-driven auto-grade — auto-exposure to Target Luma, clip-limited CDF blend, percentile-anchored levels, saturation, peak-bin hue shift
KEEP VERBATIM: 4 params/roles + ranges, in-pass workgroup histogram (32×32 stratified grid, static jitter, 3 barriers in uniform control flow), HEAD bin reduction,
  exposure clamp 0.5..3.5, extended Reinhard + softEnds, contrast span/pivot/anchor, CDF clip blend (Contrast × 0.5), peak-bin hue-shift formula and its gate, A stats packing, alpha = src.a, depth pass-through, every existing Ideas: item
ADD:
  3. Luma-held saturation and hue stage (energy accounting) — the HSV Saturation multiply and the peak-bin hue rotation run at constant V, so they change luma after the
     equaliser set it. Rescale the stage's output to the pre-stage Rec.709 luma (ratio clamped 0.5..2, channels clamped to 1) so Saturation / Dynamic Hue Mode change
     colour only and Target Luma stays what the slider says. Consumes: `color` (pre-HSV) and `outColor` (post-HSV), both already in hand. 0 extra taps.
FORBID: halation, extra metering taps, springs/pointer, ACES on top of Reinhard, moving the saturation slider to a different role (vibrance) — param theft
A PACKING: raw stats field, never ACES — unchanged. (C unread; the A write stays as the documented stats field.)
```
**§12.1 interrogation.** (1) Kernel: HSV saturation is the crude approximation of "scale chroma"; the better one holds luminance (Lab/YCbCr-style). (2) Physics: a colourist's saturation control (Lightroom/Resolve) never changes brightness. (3) Promoted intermediate: the pre-HSV luma is thrown away. (6) History: C is not read today; a temporal "eye-adaptation" idea (smooth exposure against the stats A already holds) was **considered and rejected** — the host copies A→C after *every* A-writing slot, so in a chain C is often another shader's display RGBA, and any in-band sentinel for "this is my own stats" can be matched by an alpha of 1.0; it would work only in some chain positions. Centre-weighted metering was also rejected (changes what auto-exposure measures, adds integer-weight atomics for marginal gain). Vibrance weighting rejected as param theft. **Only 1 idea ships for this file; it passes §12.4 (no table row used; deletion test both ways).**
