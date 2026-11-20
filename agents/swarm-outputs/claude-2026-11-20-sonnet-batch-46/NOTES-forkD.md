# NOTES — fork D (second pass) — SwiftShader only, no real-GPU visual QA

Harnesses (this dir): `forkD_flow.mjs` (history-ring renderer + flow-quality metrics: moving textured disc, history = previous
OUTPUT as the engine copies it; `mr.mjs` binds a blank 1-layer history so optical-flow-tracer would skip LK there),
`forkD_mr_ramp.mjs` (mr.mjs + `SRCFLAT=-1` vertical ramp), `forkD_ab.sh` (interleaved HEAD/new min-of-drained-frames ratio).

## conv-structure-tensor-flow  (`Upgraded: 2026-09-08, 2026-11-20`)
ADD (Ideas line + `// ── Idea n` comments):
1. Coherence-adaptive LIC length — arm = steps*mix(0.3,1,boostedCoherency) (§12.2A structure-tensor orientation). `main()`, "Idea 1".
2. Curved streamlines — tensor re-read at each arm's midpoint, sign-aligned, faded in by midpoint coherence (§12.2A same row). `licArm()`, "Idea 2".
KEEP VERBATIM: Sobel + 3x3-box tensor weights, eigen/coherency/`pow(coh,1/boost)`, 4 params + roles, vortex + ripple disturbances, perp
  tangent (minor-eigenvector LIC), animated rotation, tent LIC 1.5 px/centre tap in both arms, palette x coh x lic + 0.32 src tint, ACES x mids, alpha, depth.
A PACKING: ACES display RGBA (unchanged, C unread).
RESCUES (HEAD defects, not ideas):
- R1 orientation hue seam: HEAD hue = atan2 of the eigenvector (not pi-periodic; x>=0 always, so horizontal structure flips t 0.25<->0.75 on the sign of
  rounding-level Jxy). A pure vertical ramp rendered purple/green STRIPES; SRC=tex 90-degree quadrant was speckle. Now hue = DOUBLED angle (full 1-periodic
  palette wheel): ramp is one colour, quadrant clean. theta=0 keeps t=0.5; tilted structure now spans the whole wheel => DEFAULT LOOK CHANGES (more rainbow). FLAG FOR USER.
- R2 `normalize(vec2(lambda1-Jyy, Jxy))` is normalize(0) when Jxy==0, Jxx<Jyy: longer-of-two-forms eigenvector, same sign as HEAD elsewhere. (SwiftShader did not NaN on HEAD's ramp, so unreproduced here.)
- R3 `pow((rDist - ...)*8.0, 2.0)` had a negative base inside the ripple ring (undefined in WGSL) -> explicit square. (Not reproducible on SwiftShader.)
- Perf-only: Sobel was recomputed at 9 offsets (108 luma taps); same tensor from one shared 5x5 window = 25 taps (named scalars; an indexed array was 4x slower on SwiftShader).
  First draft put the midpoint re-read inside the LIC loop under `if (i == nMid)`: per-pixel nMid diverges, so it re-ran per distinct nMid in a packet (~3-10x HEAD). Split into two loops.
DIFF vs HEAD (SRC=img 192px, p=.9,.4,.5,0): full vs HEAD 95% px >2/255 (mostly R1); ideas 1+2 alone vs rescue-only: 16.6% >2/255, 0.8% >8/255 (alpha mean|d| 0.009 on SRC=tex).
  The LIC term enters the picture as (0.5+0.5*lic) and a 0.32 src mix, so streak-length/curvature is a quiet change at default sliders; effect is spatially coherent (inside/around the discs: no luma smeared across disc edges).
TIMING (min-of-drained-frames, interleaved, load ~2.6): 0.86x HEAD median (0.80..1.09, 6 rounds); lic_steps=1: 0.85x (4 rounds).
GATES: precommit 1/1, naga-wasm 1/1, dead sliders PASS (all 4 read by hand), extraBuffer PASS, NaN 0 at defaults/ripples/mouse+audio/ramp/flat.
JSON: description sentence appended (visible change); params/x-meta untouched; features unchanged (still true).

## optical-flow-tracer  (`Upgraded: 2026-09-21, 2026-11-20`)
ADD (HEAD Ideas 1/2 are Shi-Tomasi + pyramid; new ones continue the numbering):
3. Gaussian-weighted LK window (§12.1 tactic 1) — sigma 0.8*half (floor 1.2), weights renormalised to the tap count so every lambda-min threshold keeps its calibration; both LK levels. `lucasKanade()`, "Idea 3".
4. Temporal flow carry through C (§12.1 tactic 6) — KLT init of the fine level from last frame's flow (semi-Lagrangian, undo flowScale, chosen only if it predicts the live pixel better, 0.01 margin) + 35% inertia gated to |v|>0.5 px and photometric agreement. `main()`, "Idea 4".
KEEP VERBATIM: both LK levels + prior pre-warp, Shi-Tomasi gate, pyramid + thresholds, ring indexing, cumulative backward warp per age, normalised decay weights, mix(trail,current,blend), alpha, 4 params, A raw flow, depth, extraBuffer[4].
A PACKING: raw flow field (A.xy=flow*flowScale px, A.z=|flow|*flowScale*20, A.w=1) — unchanged; now also read back raw via exact textureLoad (consistent). `A packing:` line added (HEAD had none).
RESCUE: dropped the false `mouse-driven` from header Features and JSON `features` (file never reads zoom_config.yz / ripples; §8). Observation, NOT changed: `decay` is nearly inert (weights normalised: 0.92..0.99).
FLOW QUALITY (harness, px/frame vs ground truth; HEAD -> new; sensor noise .02):
  1.5 px/frame: interior RMS 1.01 -> 0.93, halo 0.186 -> 0.115, static-background false flow 0.054 -> 0.039, temporal jitter 0.94 -> 0.88  (all better)
  3 px/frame:   RMS 2.46 -> 2.18, halo 0.187 -> 0.194, far 0.057 -> 0.040, jitter 1.43 -> 1.70  (RMS/far better, jitter +19%, halo ~)
  5 px/frame:   RMS 5.90 -> 6.45, halo 0.24 -> 0.29, far 0.061 -> 0.045, jitter 1.73 -> 2.17  (HEAD already fails: truth 5.4 px; far-field cleaner, rest worse)
  slider extremes (decay/scale/age=1, blend 0): RMS 5.5 -> 5.0, far 1.83 -> 1.24; (all 0, blend 1): RMS 1.53 -> 1.01, jitter 1.17 -> 0.55. Trade-off is inherent: Gaussian window trades interior noise for boundary sharpness, carry trades the opposite.
DIFF vs HEAD (moving disc, noise .02, defaults): rgb 8.1% px >2/255, 1.5% >8/255; alpha differs on 41% px because alpha = f(|flow|*20) and background false flow is lower (alpha is semantic, still).
TIMING: 0.97x HEAD median (0.86..1.24, 6 rounds, ring depth 4). Ring depth 1: LK skipped as at HEAD (nan 0).
GATES: precommit 1/1, naga-wasm 1/1, dead sliders PASS (4 sliders read by hand), extraBuffer PASS, NaN 0 everywhere tried.
NOT VERIFIED: real-GPU look; real video (harness is a synthetic textured disc); the engine's multi-slot chain C semantics for A→C across shader switches (stale non-flow C on the first frame after a switch gives <1 px prior for one frame, and is only used if it beats the spatial prior photometrically).
