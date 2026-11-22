# BRIEFS — fork B (optical-flow-tracer, temporal-feedback-zoom-tracer)

Written BEFORE any WGSL edit. HEAD = `/tmp/claude-0/-root-image-video-effects/547473e0-56ec-49ad-94b1-b40db5a7c127/scratchpad/coord/head/<id>.wgsl` (copied to `.../scratchpad/b/`). Harness: `agents/mr_hist.mjs` (picture), batch-46 `forkD_flow.mjs` copy (`.../b/flow_metrics.mjs`, flow accuracy).

## HEAD findings (measured)

- **zoom-tracer, audio phase scramble (rescue R1, verified):** `clockRings = sin(r*95 - time*(5 + treble*7))` and `spectral` hue `time*(0.8 + mids)` multiply ABSOLUTE session time by an audio value. Any audio change late in a session moves the phase by `time*Δaudio` radians. Measured: single frame, treble 0.10 vs 0.12, mean |Δpixel| = 0.0023 at time 0.5 s but 0.0257 at time 60 s (11x): the rings re-scramble on every audio fluctuation after the first minute. Fix: constant time rate; audio becomes a bounded phase offset (`- treble*4`, `+ mids*2`), still audio-reactive, no scramble.
- **zoom-tracer, always-on rainbow "clock ring" overlay** dominates the default picture (rings at 95 rad/uv, additive 0.05-0.1, written into the ring so it compounds with the zoom) and the tunnel reads at ~0.48x source brightness (meanL .197 vs ~.41: persistence x (1-blend) x feedback-camera falloff compound to loop gain ~.66). The overlay is older than this pass and not on the `Ideas:` line. **Left in place; flagged as an open call for the user.** The dim tunnel is the consequence of the shipped falloff idea (stacked per pass).
- **zoom-tracer, tags:** `upgraded-rgba` in `Features:` and JSON `features` with no ACES; output is a photo/ring composite whose emissions are LDR (bezel mixes toward 0.92-1.0, overlay <= ~0.35) -> P-ACES (c): drop the tag.
- **optical-flow-tracer:** the trail's last age is a hard cutoff and `maxAge = 1 + u32(z*4)` makes the `Trail Age` slider step in 5 stairs; `let t = f32(age)/f32(maxAge+1)` was clearly meant as a taper and is dead (never read). The trail is a straight-line extrapolation: one flow vector for all ages. Ring holds this shader's OWN previous output (engine: `blitReadTex` -> ring), so history contains earlier trails (compounding, by design).
- **optical-flow-tracer, flow accuracy (batch-46 metric, 128 px):** rms error inside the disc 0.73 px @ v=1.1 px/frame, 2.1 px @ 3.4, 8.7 px @ 6.7 (flow collapses to ~0 at high speed; the coarse level reaches ~+-4 px). It is batch-46's solver; **not touched** here (out of scope, no cost headroom), recorded as an open note.
- **optical-flow-tracer, tag:** `upgraded-rgba` in `Features:` / JSON with no ACES, and A is raw flow (documented "Not ACES'd") -> P-ACES (c): drop the tag.
- Nothing in either file writes `extraBuffer[0..132]`; `dataTextureC` is read exactly (flow tracer) / not used (zoom tracer). No C feedback invented.

---

SHADER: temporal-feedback-zoom-tracer
IDENTITY (one sentence): a video-feedback tunnel — the previous ring frame re-read through a zoom + roll about the pointer-led focus, chroma-split, fbm-jittered, blended with the live frame; nested monitor bezels and hue drift stream out of the focus.
KEEP VERBATIM: 4 params and roles (zoom -> zoomFactor/jitter/chroma/bezel strength; rotation; persistence 0.92-0.99; blend 0.05-0.40); focus = mix(0.5, mouse, 0.7); fbm jitter; chromatic history; Ideas 1-4 on the `Ideas:` line (nested monitor bezels; recursion hue drift; field lag; feedback-camera falloff); A = display RGBA (unchanged); clock-ring + click overlay (left, flagged); dark surround outside the frame.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): the kernel is an affine warp. The next-better approximation of a real camera-on-monitor loop is a PROJECTIVE warp (a camera is never square to the screen).
  tactic 2 (physics one step further): a camera filming its own monitor also runs auto-exposure; the loop's brightness is regulated, which is what keeps real feedback tunnels lit instead of decaying (HEAD's tunnel settles at ~0.48x source).
  tactic 3 (promote an intermediate): `histWarp` is already computed; its mean level is the quantity an AGC meters. `focus`/`mouse` already exist and are the "aim" of the camera.
  tactic 6 (use the history it owns): the ring is read at age 1/2 for the warp; the same ring (age 1) is metered for exposure with zero new bindings.
ADD:
  5. **Keystone tilt (§12.1 tactic 1)** — the warp divides by `1 + dot(rotated, tilt)`: a camera that is not square to the monitor leans the tunnel, so its vanishing point curves and the nested copies spiral off-axis instead of marching straight out. `tilt` = slow hand-held sway (two incommensurate sines) + the pointer's offset from centre (the pointer already aims the camera), amplitude scaled by the zoom param. Zero at mouse centre only for the pointer term; the sway is always on, small.
  6. **Auto-exposure loop gain (§12.1 tactic 2)** — meter the age-1 ring frame on a 3x3 grid and the live frame on the same grid; scale the history by `sqrt(Lsrc/Lhist)` clamped to [0.9, 1.4]. Negative feedback (exponent 1/2 on a one-frame delay is stable, no hunting runaway), source-relative so a dark video is not boosted past itself. Lifts the settled tunnel from ~0.44x to ~0.70x of source, and pumps when a bright object enters, as a camera does.
  R1 (rescue, not an idea): audio phase scramble (above).
FORMULA ADMISSION: no §12.2 row used (domain-native: camera optics + AGC). Both consume quantities the file already has (the warp's `rotated`/`focus`; ring age 1; live frame). Deletion test: deleting either leaves HEAD's tunnel exactly; keeping only either is not a different effect. Same-noun test: "camera tilt", "camera auto-exposure" — both nouns of the feedback-camera device that idea 4 (falloff) already names.
FORBID on this file: new springs, new params, IQ palette, a second overlay, ACES on the photo path, touching `params`.
A PACKING: display RGBA (unchanged).

---

SHADER: optical-flow-tracer
IDENTITY (one sentence): Lucas-Kanade motion estimate that drags a decaying ghost trail through the history ring along each pixel's own trajectory; static areas stay a clean frame.
KEEP VERBATIM: 4 params and roles (decay, flowScale, trailAge, blend); pyramidal LK (coarse 3x3 stride 4 + fine 5x5 stride 1); Gaussian window; Shi-Tomasi gate; KLT carry through C with hysteresis; 35% inertia; Ideas 1-4 on the `Ideas:` line; **A = raw flow field (A.xy = flow*flowScale, A.z = |flow|*flowScale*20, A.w = 1), read back by exact `textureLoad(dataTextureC)` — not ACES'd, unchanged**; alpha formula; depth passthrough.
MECHANISM INTERROGATION:
  tactic 2 (physics one step further): a trail is a long EXPOSURE: the shutter integrates continuously along the path; HEAD takes one point sample per age, so copies are discrete and the trail ends in a hard cut at `maxAge` (the dead `t` variable shows a taper was intended).
  tactic 3 (promote an intermediate): `prevFlow` (last frame's flow where this content was, already loaded for the KLT carry) and `flow` (this frame's) are both in registers; their angle is the turn rate nobody uses.
  tactic 4 (second-order the parameter): `Trail Age` is a stair (1..5 ages); its spatially/continuously varying version is a fractional last age.
  tactic 6: C already returns last frame's flow; it is enough to bend the trail without new state.
ADD:
  5. **Shutter integration along the path (§12.1 tactic 2)** — each age's ring read becomes the mean of two taps, at the previous and current warp position (trapezoid over the segment), so a fast mover leaves a continuous streak instead of separated ghost copies. +`trailAge` ring taps, no change when the segment is under ~1 px.
  6. **Comet taper (§12.1 tactic 4)** — `trailAge` becomes continuous: the last age enters with fractional weight and every age is tapered (`1 - t`, the HEAD intent), so the streak thins to nothing instead of ending in a hard edge; the slider no longer jumps in stairs.
  7. **Constant-turn-rate trail (§12.1 tactic 3)** — the trail walks back along the CURRENT flow rotated by `-omega` per age, `omega` = signed angle from `prevFlow` to `flow` (gated: both >= ~1 px, clamped +-0.3 rad/frame, only where the KLT carry is valid). Orbiting / swinging objects leave an arc, not a tangent line. Costs nothing extra (both vectors already exist). Dropped if the orbit test shows it is noise.
FORMULA ADMISSION: no §12.2 row except "semi-Lagrangian ... only optical-flow-tracer" which I do NOT use (C cannot carry a path: only the live mover has flow in last frame's field). Domain-native (exposure, kinematics). All consume quantities the file computes. Deletion test: each removal leaves HEAD's straight, stepped trail.
FORBID on this file: new LK work / a second flow solve (cost: HEAD ~3.3 s/frame @256), changing the A packing, ACES on A or the photo, springs, a flow-direction colour wheel overlay, new params.
A PACKING: raw flow field in A (documented, unchanged). Ring still gets the output (engine).
COST BUDGET: +<= ~7% (5-6 extra ring taps vs ~220 samples/pixel); cap 1.3x.
