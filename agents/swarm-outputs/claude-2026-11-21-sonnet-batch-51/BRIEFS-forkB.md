# BRIEFS — fork B (prismatic-feedback-loop, echo-trace) — written BEFORE any WGSL edit

HEAD = worktree file after the coordinator's prelude migration (copies in scratchpad `b/<id>_head.wgsl`).

## Discovery that changes the job: both files were upgraded before and the upgrade was wiped

`git log -S'Ideas' -- public/shaders/<id>.wgsl` shows:

| file | lost upgrade | wiped by |
|---|---|---|
| echo-trace | `001c634d` opus/batch-27 (3 ideas + the exact rescue Finding 1/2 describes) | `9b5cd56e` google-labs-jules[bot], 2026-11-09 21:22Z, "Fix rotate and float errors, update prelude_migration" |
| prismatic-feedback-loop | `9acc4b18` sonnet/batch-28 (2 ideas + spring rescue) | same commit |

`9b5cd56e` rewrote 22 shader files back to their pre-upgrade text and deleted the batch-27/28 notes. Same failure mode as the 2026-11-08 jules revert (see memory "Branch Salvage"). So for these two files the work is a **verified salvage + defect fixes**, not an invention. The Idea Cards below were written from my own reading of HEAD and of the lost versions; the lost text is the candidate implementation. Each lost version is re-verified (naga-wasm, engine-faithful harness, NaN, packing) and corrected where it has defects (listed per card).

## prismatic-feedback-loop

### What HEAD does (read in full, rendered)

One pass. Prism taps: `centered = uv − 0.5 + held warp`, rotated by `time·0.1` (`drift`), R tap = `uv + rot(drift, +fan)·spread·depthScale`, B tap = `uv − rot(drift, −fan)·spread·depthScale`, G in place; click bursts add a radial R/B kick for 1.5 s. `blended = clamp(mix(prev.rgb, prismColor, feedbackMix))` — **`prev` is read at the same pixel**, so the "feedback loop" is only a temporal low-pass of a prism-split photo: no spatial recursion. `accumulativeAlpha` writes raw `(rgb, a)` to A (read back as C colour + alpha); glow `trailLum²·glow·0.6`; ACES only on `writeTexture`; depth passthrough.

HEAD renders (SwiftShader, 192², SRC=img, 90 frames, params 0.5/1/0.8/0.02, audio .3/.2/.1): idle `meanL .513 stdL .173 meanA 1.0 nan 0`; pointer held, sweeping (0.15,0.5)→(0.85,0.5) in the engine-faithful harness: identical `meanL .513` — the held warp is local and tiny.

**Spring (Finding 2) — dead in the engine, garnish here.** `extraBuffer[133..138]` is zeroed every frame ⇒ `initialized == false` ⇒ `prismFocus = rawMouse`, `springVel = 0`, always. The "sprung held deformation" is raw pointer with no lag, no velocity. Not the identity (the identity is the prism), so a minimal glide in A texel (0,0) is a fix of a claimed feature, reported as a **rescue**, and no idea depends on it.

Other HEAD notes (reported, **not changed**): the `Feedback` slider is inverted against its label (`mix(prev, new, x)`: x=1 means *no* feedback) — changing it would flip saved presets, out of scope; features tags `spring-interaction` / `depth-aware` over-claim at HEAD (depth only scales taps).

### Idea Card

```
SHADER: prismatic-feedback-loop
IDENTITY: the photo through a slowly rotating chromatic prism (R and B taps fan apart about the
  optical axis) with a temporal feedback accumulation, a glow on the trails, a held-pointer warp
  and click prism bursts.
KEEP VERBATIM: the 4 sliders and roles (x Feedback = mix toward new, y Blur Radius = tap spread,
  z Glow Intensity, w Chromatic Spread = r/b fan angle); prism tap geometry (rot2(centered,
  time*0.1), ±chromaFan, depthScale); click bursts (RIPPLE_LIFE 1.5, kick 0.06); accumulativeAlpha
  chain and the [0,1] feedback clamp; glow term; ACES on the display write only; depth passthrough;
  A = raw accumulated RGBA read back as colour+alpha.
ADD (2 native ideas):
  1. Prism echo — the history is read back through the same prism (R from C displaced with the red
     tap, B from C displaced against the blue tap, G in place; exact 4-tap bilinear, no filtering
     sampler). Why here: a feedback loop in optics (camera on monitor) pushes each generation through
     the lens again, so fringes compound into spectral spirals; HEAD's history never moves.
  2. Cauchy-weighted taps (§12.2F) — n(λ)=1+B/λ² at 650/550/450 nm scales the red and blue tap
     offsets (blue refracts harder, green undeviated) instead of a symmetric ±. Why here: it is a
     prism; dispersion is not symmetric. Applies to live taps, click kicks and the echo.
RESCUE: dead extraBuffer[133..138] spring → first-order glide kept in A(0,0).
FORBID: ripples as a new overlay, IQ palette, thin film, hue rotation per generation (a costume),
  any change to the saved params or the Feedback inversion, ACES in stored A.
A PACKING: raw accumulated RGBA (C read as colour+alpha, unchanged) EXCEPT texel (0,0) =
  (glide.x, glide.y, 7, fract(time)) — masked to 0 by every C consumer so no pixel reads it as colour.
```

### §12.1 mechanism interrogation

- **Tactic 1 (deepen the kernel).** The temporal low-pass `mix(prev, new)` approximates an optical feedback loop with unit-lens gain. The next-better approximation of the *same* operator: resample the history through the lens map (the displacement the tap already computes). Same two numbers, no new state.
- **Tactic 2 (physics one step further).** A prism disperses with a Cauchy law: n(λ) = A + B/λ² — the blue deviation is larger than the red one by a *fixed ratio*, not a mirror image. The loop adds that each generation re-disperses.
- **Tactic 3 (promote an intermediate).** `rOffset` / `bOffset` (already computed, then used for one tap each) are the lens displacement; they are reused for the history echo at no extra geometry.
- **Tactic 6 (history).** C is read as colour+alpha. The extra continuity that keeps that reading: displaced history lookup (colour stays colour). Stored A is unchanged in meaning.

### §12.4 formula admission

Cauchy dispersion: family F (prism = optics); consumes `rOffset`/`bOffset`; deleting it leaves the same prism with symmetric taps (additive), deleting the prism leaves nothing recognisable. Prism echo is **not a §12.2 row** (it is tactic 6 on this file's own mechanism). Row claims: Cauchy dispersion is also claimed by prismatic-3d-compositor (fork A) — two files is the §12.4 limit, so the coordinator must not add it to a third.

## echo-trace

### What HEAD does (read in full, rendered)

Kalman pointer estimator (state pos+vel, covariance), structure-tensor flow of the photo, Mahalanobis-ellipse dashed predicted trail, brush stamp at the updated position, advect from C, oil-slick tint keyed to Mahalanobis, capped click sparks, hue shift, ACES, depth write.

**HEAD is dead (verified here, not only by reading):**
- Idle: `meanL .078 stdL .027` against a source of ~0.5; sweeping pointer `(0.15,0.5)→(0.85,0.5)`: `meanL .331 stdL .077` — output is a **violet plate with rectangular covariance blocks** (`b/echo_head_move.png`); the photo never shows except in a small blob under the pointer.
- **A packing lie:** `dataTextureA = [pPos·300, pPos·300, pVel·45, pVel·45]` (covariance diagnostics) but `history = textureLoad(dataTextureC, coord)` is blended as **colour** (`color = mix(history.rgb, echo, …)`) and the display is built on it, so the "colour history" is a covariance field.
- **Dead Kalman:** state lives in `extraBuffer[133..141]` (zeroed every frame) ⇒ `initialized` is always false ⇒ `updatedVel = 0`, `innovation ≈ 0` ⇒ `residualMag = 0` ⇒ `predictedTrail = smoothstep(0.002,0.08,0) = 0`: the dashed predicted trails (the identity) never draw. dt hard-coded 1/60.
- `pow(neg, 2.0)` does not exist at HEAD here; it is in the lost version (see below).

### Idea Card

```
SHADER: echo-trace
IDENTITY: a Kalman pointer tracker over the photo — the predicted path is drawn as Mahalanobis-shaped
  dashed trails, a tight brush stamps the photo into a fading structure-advected trail layer, clicks
  leave spark echoes.
KEEP VERBATIM: the 4 sliders and roles (x prediction_horizon → sigmaA + trail gain, y velocity_smoothing
  → sigmaM, z trail_deformation → brush width, w velocity_threshold → velGate); the Kalman equations
  (sigmaA/sigmaM/qPos/qVel/rPos, gains, covariance update); ellipse + dashed predictedTrail; held
  tightening (dash scale/brush ×0.55); recentTrail brush; structure-tensor advect `advectUV`; oil-slick
  film tint; click sparks (capped 50, 48-cycle rings); hue_shift; ACES on the display write only; depth write.
ADD (3 native ideas, all from the estimator's own state):
  1. Kalman lag ghosts — three tinted image copies stamped at pos − vel·k behind the cursor, k = n·
     (0.05 + horizon·0.15). Why here: a velocity estimator *knows* where the pointer was; the ghosts
     show the filter's smoothed history, gated by speed.
  2. Redshift aging — low-energy (old) echo drifts warm, fresh echo stays cool. Why here: the trail
     layer now carries an energy channel; ageing an echo is the "echo" in the name.
  3. 2σ covariance ellipse outline — `ring2` at Mahalanobis radius 2 around the predicted position.
     Why here: the file already computes `maha` (tactic 3); the 2σ contour is how a Kalman
     uncertainty is drawn.
RESCUES (reported separately, not counted as ideas):
  R1 A packing lie → A = linear trail RGB + echo energy (what C is read as).
  R2 dead Kalman → state moved from extraBuffer[133..141] into A texels (0,0) pos+vel, (1,0) pPos +
     pVel.x + sentinel 7, (2,0) last time + pVel.y; real frame dt from the stamped time.
  R3 mask: every read of C at those three texels is zeroed so no pixel reads state as colour.
  R4 pow((sqrt(maha)−2)·6, 2.0) in the lost version has a possibly negative base → x·x.
  R5 pVel.y was squeezed into a clamped sentinel in the lost version (asymmetric filter) → full float
     in texel (2,0).y.
FORBID: new params, new springs, IQ palette beyond the existing film tint, replacing the Kalman by a
  plain smoothed cursor, ACES in stored A.
A PACKING: A.rgb = linear trail colour, A.a = echo energy (C is read as colour+energy); texels (0,0),
  (1,0), (2,0) = Kalman state (masked on read). B untouched. extraBuffer untouched.
```

### §12.1 mechanism interrogation

- **Tactic 1 (kernel).** The Kalman gain/covariance update is already the right operator; what is approximate is the *trail* (a 2-tap mix + advect). Deepen: add an energy channel that fades and ages (tactic 2).
- **Tactic 2 (physics one step further).** An echo is a delayed, attenuated copy; older echoes lose energy and shift hue (the redshift). A tracker shows 2σ uncertainty contours and past-estimate ghosts.
- **Tactic 3 (promote an intermediate).** `maha` (→ ring2), `updatedVel` (→ lag ghosts), `uncertainty`, `velGate` are computed and used once; the ghosts and the outline reuse them.
- **Tactic 6 (history).** C was read as colour but A held covariance. The truthful reading is colour+energy; the minimal extra continuity is the energy channel in A.a.

### §12.4 formula admission

None of the three are §12.2 rows (they are tracker/echo vocabulary: tactics 2, 3, 5). Family match: interactive / brush (pointer-owned file, estimator). They consume `updatedVel`, `maha`, `energy` that the file computes; no new solver; deletion test passes both ways (delete the ghosts → same Kalman trail; delete the Kalman → nothing is left).
