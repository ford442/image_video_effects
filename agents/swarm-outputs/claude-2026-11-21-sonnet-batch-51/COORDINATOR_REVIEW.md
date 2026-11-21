# COORDINATOR REVIEW — sonnet/batch-51 (7 files, 4 forks)

Base: origin/main 49395199. Branch `sonnet/batch-51`. Real-GPU visual QA: external — every picture claim below is SwiftShader-harness only.

## How the batch was chosen
The user pasted nine ids that sonnet/batch-49 (PR #1720) had already upgraded and merged; they chose "pick a fresh batch". A scan of origin/main for files with no idea text in ANY format leaves 29 files; 22 are multi-pass pipeline stages or are claimed by the live session in /root/iv-sonnet-batch-50 (cosmic-web). These seven are the standalone effects left.

## Correction to COMMON.md
- Finding 3 was wrong for `prismatic-3d-compositor`: its Pass 1 exists (`volumetric-rainbow-clouds`, already ACES'd). Fork A found it.
- Four of the seven (compositor, feedback-loop, echo-trace, psy-swirls) had been upgraded in batches 27/28 and were reverted by jules-bot commit `9b5cd56e` (2026-11-09, 22 shaders, notes deleted). Forks B, A and C audited the lost versions rather than copying them; D and the rain/alucinate files had no history. The coordinator's "first pass" label in COMMON.md was therefore wrong for those four; they are **salvage + new ideas**. murmuration-flock / murmuration-render were also reverted by 9b5cd56e but are pipeline stages, not in this batch.

## Per file (pass = every idea pointable in the WGSL, KEEP VERBATIM holds, params byte-exact, A packing truthful)

| id | ideas (§12.2 row) | rescues | A packing | timing (re-timed by coordinator, loaded box) | verdict |
|---|---|---|---|---|---|
| rain | per-lane terminal velocity + exposure-length streaks; Snell refraction through each streak (F); Beer–Lambert mist on scene depth (F) | rain fell UP; lens offset grew with time (48× at t=300 s); streaks on a perfect comb; mist strobed | unchanged diagnostics, nothing reads C | ≈1.0× | PASS |
| prismatic-3d-compositor | Cauchy dispersion on the aberration split (F); energy-conserving glow (F); depth-consistent parallax (3-step fixed point + disocclusion fade) | afterglow trail from batch-28 salvage made visible; exact C load | unchanged (trail colour + luminance alpha) | ≈1.05× | PASS, **default look changes a lot** (93 % px, meanL 0.619 → 0.507) |
| prismatic-feedback-loop | prism echo (history re-read through the prism); Cauchy-weighted R/B taps (F) | dead spring → glide in A texel (0,0); half-texel resample drift (stdL 0.181 identity restored); black corner pixel | raw RGBA; texel (0,0) = glide state, read back as (1,0) | ≈1.2× (1.19–1.22) | PASS |
| echo-trace | Kalman lag ghosts; redshift aging; 2σ covariance outline | **photo was gone** (A held covariance, C read as colour: meanL 0.078 → 0.48); dead Kalman → state in A texels (0..2,0), predictedTrail 0 → 241/255 on an abrupt-motion probe | A.rgb trail colour + A.a echo energy; texels 0..2 of row 0 = filter state | 1.14–1.27× vs a dead HEAD (ratio not meaningful) | PASS |
| alucinate | IFS fold-count chirality (E); IFS orbit-trap veins (E); Turing-cell lenslets | click ripples on a half-rate clock vs session time (picture became rings for ~10 s); ripple cap 50; A.z true gradient | raw field, no reader | ≈1.0–1.04× | PASS; **no ACES by design** (flattens this high-key remix) |
| generative-psy-swirls | Lamb–Oseen core wring (E additive domain twist); per-channel flow lag; salvaged arm-wound hue + Rankine eye-wall | dead spring → glide in A texel (0,0) (salvaged) | raw trail colour (clamp 1.2); texel (0,0) = glide | ≈1.10× (5 runs 1.08–1.12) | PASS; 4 ideas = the ceiling |
| liquid-smear | bank-and-wake (D shallow-water continuity); bristle rake (C); speed-thinning (C) | dead pointer drag (speed was 0.000); dead FFT band (`plasmaBuffer[1..8]` never uploaded → `extraBuffer[5+4b]`) | pre-ACES pigment + alpha; texel (0,0) = pointer state | ≈1.03× | PASS; **weak visible gain** (HEAD's drag is gentle; lanes ~1.5/255) |

## §12.4 de-dup
- Cauchy dispersion on **two** files (compositor, feedback-loop) — at the cap; they differ on every other idea. Beer–Lambert on two (rain, liquid-smear display shade). Every other row is on one file.
- No spring/ripple/IQ-palette overlay stamped across the batch. The glide in A texel (0,0) is a **rescue** on four files whose identity is pointer-led (feedback-loop, echo-trace, psy-swirls, liquid-smear), not an idea.

## Gates (coordinator, final tree)
naga-wasm 7/7 · precommit 7/7 · dead sliders 0 new · extrabuffer audit pass · `verify:shaders:fix` 11/11 · `params` byte-exact on all seven definitions (only `description` changed) · `upgrades:record` scoped `--ids=` · `npm run build` ok.
Vitest: 220/221 files pass; the failures differ run to run (1 test in one run, 2 `RendererManager` timer tests in the next, both `setTimeout(20)`-style) and `RendererManager.test.ts` passes 56/56 alone twice — flake on a box at load 16–35 from another session's Playwright jobs. The diff touches no `src/` code (only `src/contracts/prelude_migration.json`).

## Open calls for the user
1. **Engine:** `writeExtraBuffer` (`src/renderer/webgpu/audioDepth.ts`) rewrites all 256 floats every frame, so `extraBuffer[133..255]` is zero at every dispatch. 222 catalog shaders keep "persistent" state there and `WGSL_BUILTINS_GENERATIVE.md` still calls it safe. Writing only `[0..132]` is a one-line change but alters 222 shaders at once — **not done here**.
2. Compositor default look (above). `GLOW_EMIT = 0.75` is the single dial, tuned by eye; lowering toward 0 approaches HEAD. Batch-28's cursor light shafts were not re-added (the pointer only drives parallax here).
3. Tuned by eye, need a real photo on a real GPU: rain `LENS_GAIN` and haze coefficient; liquid-smear bristle lanes; psy-swirls wring amplitude. Rain's mist depth direction is reversed vs HEAD (farther = more haze).
4. Over-claiming tags left alone: rain `chromatic`; compositor `upgraded-rgba` with no ACES; feedback-loop `spring-interaction`/`depth-aware`; alucinate `upgraded-rgba` with no ACES; psy-swirls `sprung-mouse-vortex` (now a first-order glide). The feedback-loop "Feedback" slider is inverted against its label; flipping it would invert saved presets.
5. `psy-swirls.json` shares this WGSL with different slider names (x default 1 = full twist).
6. Harness: `agents/mr*.mjs` (gitignored) now re-zero `extraBuffer[133..255]` per dispatch like the engine. Before that, the harness showed springs working that die in the real engine.
