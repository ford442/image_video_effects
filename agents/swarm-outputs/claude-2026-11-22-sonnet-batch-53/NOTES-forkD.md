# NOTES — fork D (tone-histogram, tone-histogram-apply), sonnet/batch-53

Cards: `BRIEFS-forkD.md` (written before the WGSL). Scratch + renders: `/tmp/claude-0/-root-image-video-effects/0808efa3-e4d2-4c02-b58e-093c2450d257/scratchpad/d/` (`sheet_th.png`, `sheet_ap.png`: source | HEAD default | NEW default | HEAD extreme | NEW extreme on three synthetic photo scenes `src_land/dim/hazy.png` borrowed from batch-48 via `mr_photo.mjs` + `SRCPNG=`; the repo's jpgs are LFS pointers). Not committed. Real-GPU visual QA not done (SwiftShader only; the scenes are synthetic).

Pair relationship: **independent** (apply builds its histogram in-pass from `readTexture`; nothing flows from tone-histogram). JSON `multipass.prevShader` / registry entry untouched (coordinator-owned). No extraBuffer writes (or reads) in either file; neither JSON makes a false feature claim (checked, nothing removed/added).

## tone-histogram (3rd pass) — 2 ideas, 1 rescue folded into Idea 5
**ADD**
- **Idea 5 — H&D exponential shoulder knee (§12.2A, row "H&D characteristic curve")**: `filmCurve` shoulder is now `y = k + (1−k)(1−exp(−(x−k)/(1−k)))` above knee `k = 1 − 0.5·Shoulder` (value/slope-continuous). Shoulder 0 ⇒ k = 1 ⇒ identity. Applies to the luma curve and the three dye-channel curves (×1.08/1/0.92 kept).
- **Idea 6 — chroma follows the tone curve (hue-preserving ratio)**: colour difference × `mix(1, clamp((curvedLuma+0.02)/(luma+0.02), 0.6, 1.8), 0.75·Stretch)`; Stretch 0 ⇒ HEAD.
**RESCUE verified on HEAD:** Shoulder Strength 0→1 moved **max 2/255, 0.0 % px > 2/255** (toe 0→1: 16 %, max 11) — HEAD *lifted* highlights (≤0.3·(1−x)) which ACES then flattened. NEW shoulder 0→1: **20.8 % px, max 12/255** on the synthetic photo (more on real highlight-rich content).
**KEEP VERBATIM (held):** 4 params/roles, 3×3 localStats, spot meter + meterWeight, adaptGain gate/clamp, coarseMean Wallis pull, toe half of filmCurve, dye shoulder multipliers, split tone, density grain, held-pointer zone, Koschmieder inversion, ACES, alpha, all existing Ideas.
**A packing:** ACES display RGBA, C unread — unchanged, truthful.
**Diff vs HEAD (pixels > 2/255):** identity at Stretch 0 / Shoulder 0 = **bit-exact (max 0/255)**. Defaults: synthetic-photo harness 3.4 % (max 7); scenes land 54.6 % (max 8) / dim 26.5 % (max 7) / hazy 0.0 %. Stretch 1 + Shoulder 1: 35 % (max 14) harness; land 92.8 % (max 27) / dim 69 % (max 16) / hazy 0.2 %. meanL unchanged to ±0.003. **Default look changes slightly** (highlights roll off instead of lift; shadow/foliage colour a little richer when Stretch > 0).
**Timing (SwiftShader, interleaved, 256², 6 rounds, box load 43–45):** min-ratio 1.01×, paired-median 1.09×. No new taps; +4 `exp`.
**Gates:** precommit PASS, naga-wasm 1/1, dead-sliders 0, extraBuffer PASS. NaN 0 on flat 0 / 0.5 / 1 and Stretch/Toe/Shoulder = 1 with mouse down + audio 1,1,1.
**JSON:** `description` appended (visible behaviour changed); `params` byte-exact vs origin/main (json equality); `features` unchanged (all true: audio via plasmaBuffer, pointer meter, depth haze, ACES).

## tone-histogram-apply (3rd pass) — 1 idea (no second idea passed admission)
**ADD**
- **Idea 3 — luma-held saturation and hue stage (energy accounting)**: output of the HSV Saturation multiply + peak-bin hue rotation is rescaled to the pre-stage Rec.709 luma (`clamp((Lpre+0.004)/(Lpost+0.004), 0.5, 2)`, channels clamped to 1). 0 extra taps.
**HEAD defect verified:** Saturation 0 / 0.5 / 1 → meanL **0.518 / 0.482 / 0.446**, local luma shift ≤ 0.15 (38/255); hue mode shifts local luma by up to 0.23 (60/255). NEW: meanL **0.499 / 0.498 / 0.492**; hue-mode max local shift **0.031**. (Saturation 1 keeps a 0.105 max local shift where a saturated bright pixel clips at 1.)
**Rejected on the card (reasons in BRIEFS):** temporal eye-adaptation against the A stats (host copies A→C after every A-writing slot, so C is often another shader's RGBA and no sentinel is robust); centre-weighted metering; vibrance weighting (param theft).
**KEEP VERBATIM (held):** 4 params/roles + ranges, in-pass workgroup histogram (barriers in uniform control flow), bin reduction, exposure clamp, extended Reinhard + softEnds, contrast span/pivot/anchor, CDF clip blend, hue-shift formula + gate, A stats packing, `alpha = src.a`, depth pass-through, both existing Ideas. **No ACES (Reinhard is its tone curve; unchanged on purpose).**
**A packing:** raw stats field `(exposure/3.5, meanLuma, peakBinNorm, saturation)` — unchanged; C unread (the A write is documented but dead data).
**Diff vs HEAD (> 2/255):** identity check at Saturation = 0.2667 (⇒ ×1.0) with hue mode off: max 1/255, 0.0 % px (the stage is a round-trip). At defaults: harness meanL ≈ same, scenes land 44.3 % (max 14) / dim 28.0 % (15) / hazy 59.0 % (15); meanL HEAD→NEW 0.508→0.518 / 0.452→0.460 / 0.501→0.512 (default saturation 1.175 no longer darkens). At Saturation 1 the sky stays light instead of deepening (0.492→0.517 land). **Default look changes** (a few % brighter, colours a touch paler than HEAD at Saturation > 0.27).
**Timing:** interleaved 6 rounds, 256², box load 44: min 0.95×, paired-median 1.00×.
**Gates:** precommit PASS, naga-wasm 1/1, dead-sliders 0 (all 4 params live), extraBuffer PASS. NaN 0 on flat 0 / 0.5 / 1 and hue mode on flat 0.05.
**JSON:** `description` appended; `params` byte-exact; features/tags unchanged.

## Open calls / flags for the coordinator
1. tone-histogram Idea 5 **flips the shoulder's direction** (HEAD lift → film roll-off), so saved presets with Shoulder > 0 render highlights slightly dimmer. Delete Idea 5 if the user wants Shoulder's old (near-invisible) character.
2. tone-histogram-apply default brightness/colour moves a few % (Idea 3). Only one idea shipped for apply — the file was upgraded yesterday and nothing else passed §12.4 honestly.
3. `tone-histogram-apply.json` still carries `multipass.prevShader: "tone-histogram"` / `multi-pass-2` although the shader is self-contained; chained after tone-histogram it would double tone-map. Registry/JSON are coordinator-owned — not touched.
4. Timing was taken at box load 43–45 (other forks): treat ratios as ±0.15; coordinator quiet-box re-time owed if desired.
