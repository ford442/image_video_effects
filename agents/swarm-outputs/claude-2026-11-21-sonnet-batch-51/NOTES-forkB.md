# NOTES — fork B (prismatic-feedback-loop, echo-trace)

Both files were **salvages of upgrades that existed and were wiped**, not first-pass inventions (see BRIEFS-forkB.md): `9b5cd56e` (google-labs-jules[bot], 2026-11-09 21:22Z, "Fix rotate and float errors") rewrote 22 shader files to their pre-upgrade text and deleted the batch-27/28 notes. Lost versions: echo-trace `001c634d` (opus/batch-27), prismatic-feedback-loop `9acc4b18` (sonnet/batch-28). I re-verified each, found real defects in both lost versions, fixed them, and re-gated. Files touched: `public/shaders/prismatic-feedback-loop.wgsl`, `public/shaders/echo-trace.wgsl`, `shader_definitions/interactive-mouse/prismatic-feedback-loop.json` (description only), `shader_definitions/artistic/echo-trace.json` (description only). Nothing committed.

## prismatic-feedback-loop

- **Idea Card ADD:** (1) prism echo — history re-read through the same prism (R from C displaced with the red tap, B against the blue tap, G in place); (2) Cauchy-weighted taps (§12.2F Cauchy dispersion, `cauchyScale(0.2)`: R ×0.887, B ×1.197) on live taps, click kicks and the echo. Both marked `// ── Idea n:` in the WGSL.
- **KEEP VERBATIM:** 4 sliders + roles (Feedback = mix toward *new*, Blur Radius = tap spread, Glow, Chromatic Spread = fan angle); prism tap geometry; click bursts; accumulativeAlpha + [0,1] clamp; glow; ACES on `writeTexture` only; depth passthrough.
- **A packing:** raw accumulated RGBA, C read as colour+alpha (unchanged). Texel (0,0) = `(glide.xy, 7, fract(time))`; every C reader uses texel (1,0) there (`loadHist`) so the corner pixel is not state and not black.
- **Rescue:** held-pointer spring was in `extraBuffer[133..138]` (zeroed every frame → always raw pointer, zero velocity). Now a first-order glide in A(0,0) (omega 10 as HEAD), lag vector `(raw − glide)·omega` as the velocity proxy. Proof it is alive in the engine-faithful harness: 4,523 of 36,864 px (12 %) differ against a copy with the glide velocity forced to 0 on a held sweep.
- **Defects found in the lost batch-28 version (fixed here):**
  1. *Half-texel drift per generation:* `histBilinear` used `uvp·res − 0.5` while `uv` here is `global_id/res` (no +0.5), so every frame the history was resampled half a pixel off → continuous blur + drift. Measured with spread 0 / fan 0 / feedback 0.1 / 150 frames (loop should be identity on a static photo): HEAD stdL 0.181, lost version 0.168, fixed 0.181 (= HEAD). Fixed by sampling at `coord + displacement-in-pixels`.
  2. *Black corner pixel:* the masked state texel returned 0 → pixel (0,0) was (55,86,128) vs neighbours (55,149,129). Mask now substitutes texel (1,0): corner pixel (113,149,129).
  3. *Cost:* 8 history loads for two bilinear lookups measured 1.15–1.55× HEAD → replaced by a 2-tap linear lookup along the dominant displacement axis (4 loads): paired medians 1.04 / 1.05 / 1.10 / 1.17 / 1.21 (median ~1.10) at load average ~69, ≤ 1.3× cap.
- **Diff vs HEAD:** idle default (192², 90 frames) 53.6 % of px differ >2/255, mean abs diff 1.92/255 (subtle Cauchy fringe asymmetry); high Feedback/Spread (0.9/6/1.5/0.15, 200 frames) 91.2 %, mean 9.21. meanL .513 → .513 (idle), .541 → .549 (hi). nan 0 in every run.
- **Gates:** precommit 1/1, naga-wasm 1/1, dead sliders 0 new, extrabuffer audit pass, no `pow`, no extraBuffer access left (only comments).
- **Left alone, for the coordinator/user:** (a) the **Feedback slider is inverted against its label** (`mix(prev, new, x)`: 1 = no feedback) — flipping it would reinvert saved presets; (b) features tags `spring-interaction` (now a first-order glide) and `depth-aware` (depth only scales taps) over-claim; (c) engine-level: `writeExtraBuffer` zeroing `[133..255]` (222 shaders affected) is an engine decision, `src/` untouched.

## echo-trace

- **Idea Card ADD (all from the estimator's own state):** (1) Kalman lag ghosts — three tinted image copies at `pos − vel·k`, speed-gated; (2) redshift aging — old (low-energy) echo drifts amber; (3) 2σ covariance ellipse outline (`maha` radius 2). No §12.2 rows (tracker/echo vocabulary, tactics 2/3/5).
- **KEEP VERBATIM:** 4 sliders + roles; Kalman equations (sigmaA/sigmaM/q/r/gains/covariance); dashed Mahalanobis predicted trail; held tightening; recentTrail brush; structure-tensor advect; oil-slick film tint; click sparks (≤50); hue_shift; ACES display; depth write.
- **A packing:** A.rgb = linear trail colour, A.a = echo energy (C read as colour+energy). Texels (0,0) = pos.xy/vel.xy, (1,0) = pPos.xy, pVel.x, w = 7 sentinel, (2,0) = (last time, pVel.y). All C reads at those texels use the texel below (`loadTrail`).
- **Rescues (reported separately from ideas):**
  1. *A packing lie.* HEAD stored covariance diagnostics in A but read C as colour → the photo was replaced by a violet plate with rectangular covariance blocks. HEAD meanL .078 (idle) / .331 (sweeping pointer) vs a ~0.5 source; now .483 / .482.
  2. *Dead Kalman.* State in `extraBuffer[133..141]` (zeroed every frame) → never initialised → `updatedVel` 0, `residualMag` 0 → predicted dashed trails never drew. Probe (circular pointer, r 0.08, 6 revs in 1.3 s, 256², debug channel): HEAD `predictedTrail` max **0/255**, new **241/255**. On a straight constant-speed sweep both are 0 (correct: the trail draws the filter's *surprise*, threshold 0.002 uv/frame — a converged filter on smooth motion is not surprised).
  3. *Real frame dt* from the time stamped in texel (2,0) (HEAD assumed 60 Hz).
- **Defects found in the lost batch-27 version (fixed here):** (a) `pow((sqrt(maha)−2)·6, 2.0)` has a possibly negative base → `ringD·ringD` (latent, unproven on SwiftShader); (b) state texels were read back as colour with no mask → `loadTrail` (corner pixels now (88,142,108) ×3 vs neighbour (88,141,107)); (c) pVel.y was squeezed into a clamped sentinel `7 + clamp(pVel.y·100, 0, 1.4)` while pVel.x was exact → asymmetric filter; pVel.y now an exact float in texel (2,0).y, sentinel exactly 7; (d) negative input to ACES: `hue_shift` of a saturated colour by up to 0.86 rad can give a negative component (red rotated 60° → (0.667, 0.667, −0.333)), and the catalog ACES fit maps negatives bright → `max(color, 0)` before ACES.
- **Diff vs HEAD:** 100 % of pixels differ (HEAD is the violet plate); not comparable.
- **Timing vs HEAD (dead, so cheaper):** paired medians 1.14 / 1.17 / 1.23 / 1.25 / 1.27 (median ~1.23) at load average ~45; within the ≤ 1.3× cap. Cost drivers: 3 ghost samples + drag sample + 4 state/trail loads.
- **JSON:** `description` only (the old text said the Kalman state lives in `extraBuffer[133..141]`); `params` byte-exact; `features` untouched.
- **Gates:** precommit 1/1, naga-wasm 1/1, dead sliders 0 new (4 sliders live), extrabuffer pass, no `pow`, no extraBuffer access.

## Harness notes (for later sessions)

- `agents/mr_circ.mjs` (untracked, gitignored) = `mr.mjs` + env `MCIRC='cx,cy,r,revs,down'` circular pointer path (linear `MPATH` never accelerates, so it cannot exercise a Kalman residual).
- The extraBuffer-zeroing patch of the harness is the coordinator's; with it, both rescues were tested under engine-faithful conditions.
- Could not verify: any real-GPU behaviour (SwiftShader only); visual quality on real footage; real-hardware cost of the 4 history loads.
