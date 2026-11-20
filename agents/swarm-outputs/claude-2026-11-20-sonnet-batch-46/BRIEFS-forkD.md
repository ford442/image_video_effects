# BRIEFS — fork D (conv-structure-tensor-flow, optical-flow-tracer) — written BEFORE any WGSL edit

HEAD = `git show origin/main:public/shaders/<id>.wgsl`. Both files are SECOND pass: earlier Ideas are KEEP VERBATIM.

HEAD findings (rendered on SwiftShADER; `forkD_flow.mjs` is a history-ring harness because `mr.mjs` binds a 1-layer blank
history, which makes optical-flow-tracer skip LK entirely):
- conv-structure-tensor-flow: (R1) orientation hue seam — `atan2(eigenvec.y, eigenvec.x)` is not pi-periodic; the dominant
  eigenvector has x>=0 always, so horizontal structure (vertical gradient, eigenvec ~ (0,+-1)) flips between t=0.25/0.75 on the
  sign of rounding-level Jxy. Rendered a pure vertical ramp (`forkD_mr_ramp.mjs`, SRCFLAT=-1): HEAD draws purple/green
  STRIPES on a field that must be one colour; the SRC=tex bottom-left (90-degree grating) quadrant is the same speckle.
  (R2) degenerate eigenvector `normalize(vec2(lambda1-Jyy, Jxy))` is normalize(0) when Jxy==0 and Jxx<Jyy. (R3)
  `pow((rDist - ...)*8.0, 2.0)` has a negative base inside the ripple ring (undefined in WGSL; SwiftShader happens to be fine,
  not reproduced) -> plain square. Tensor smoothing re-runs Sobel (12 luma taps) at 9 offsets = 108 taps; same maths from one
  shared 5x5 window = 25 taps (exact, not an idea — it pays for the ideas).
- optical-flow-tracer: A = raw flow field (flow*flowScale, |flow|, 1) with no `A packing:` line, C never read (history the shader
  owns is unused). Header + JSON claim `mouse-driven` but the file never reads zoom_config.yz or ripples (§8 metadata lie).
  Per-pixel LK flow is noisy inside a rigidly moving textured disc and leaks flow outside its rim (measured below in NOTES).
  All 4 sliders live. `decay` is nearly inert (weights are normalised) — noted, not changed (param role).

---------------------------------------------------------------------------------------------------------------------------
SHADER: conv-structure-tensor-flow
IDENTITY: structure-tensor orientation field of the photo, drawn as orientation-coloured line-integral-convolution along the edge tangent
KEEP VERBATIM: Sobel -> 3x3-box-smoothed tensor (same weights); lambda1/lambda2, coherency, `pow(coherency, 1/boost)`; 4 params and
  their roles (lic_steps 8..32, coherency_boost, flow_speed = rotation rate of the animated direction, mouse_vortex); mouse vortex and
  ripple turbulence as DIRECTION disturbances; `flowDir = perp(eigenvec)` (idea: minor-eigenvector LIC); animated rotation;
  bidirectional tent-weighted LIC with 1.5 px step and the centre tap in both arms; palette x coherency x (0.5+0.5*lic) mixed 0.32
  with the source (idea: source-luma tint); ACES x mids; alpha formula; depth passthrough.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): the LIC integrates a straight chord using the direction at the START pixel. A real LIC integrates
    along the field. Next-better approximation of the same operator: re-orient along the streamline (RK2 midpoint).
  tactic 2 (physics one step further): flow-based image abstraction (edge-tangent-flow / anisotropic Kuwahara / coherence-enhancing
    diffusion) lets the smoothing length follow anisotropy — long along clean edges, short where lambda1~lambda2 and the direction
    is noise. HEAD's streak length is a constant `licSteps` even where the tensor says the direction means nothing.
  tactic 3 (promote an intermediate): `boostedCoherency` is computed and spent on colour and alpha only; it never touches the kernel.
    Promote it to the streamline length. (`lambda1+lambda2`, the gradient energy, is the other throw-away; not used.)
  tactic 6 (history): C is never read and A is display RGBA; nothing to add without changing the packing -> not used.
  tactic 7 (direction): orientation is headless (theta == theta+pi) — the hue wheel must be pi-periodic (R1).
ADD:
  1. Coherence-adaptive LIC length — per-pixel arm length n = steps * mix(0.3, 1.0, boostedCoherency); tent weights stretch to the
     arm. Clean edges get the full streak, speckle gets a short one. (§12.2A "Structure-tensor orientation": direction AND confidence
     -> anisotropic kernel.) The `coherency_boost` slider keeps its role (it now also lengthens streaks).
  2. Curved streamlines — each arm re-evaluates the tensor orientation at its midpoint, sign-aligned with the incoming direction and
     blended toward it by midpoint coherence, so lines bend along curved contours (same §12.2A row: orientation field consumed along the path).
FORMULA ADMISSION: both consume the tensor/coherency the file already computes; no new state, binding, param or spring; deletion
  test passes both ways (delete either -> still an orientation-coloured LIC; delete the LIC -> not this effect).
FORBID on this file: new params, springs, IQ-palette changes beyond R1, any change to the Sobel/box/palette/src-tint constants.
A PACKING: ACES display RGBA (unchanged; C is not read).
RESCUES (not ideas): R1 pi-periodic orientation hue (full palette wheel, 1-periodic) — changes tilted-structure hues vs HEAD, theta=0 identical;
  R2 robust eigenvector; R3 explicit square in ripple wave; 108 -> 25 luma taps for the same tensor (perf only).

---------------------------------------------------------------------------------------------------------------------------
SHADER: optical-flow-tracer
IDENTITY: Lucas-Kanade motion vectors drag the history-ring after-images; moving objects stay aligned, the wake leaves ghosts
KEEP VERBATIM: both LK levels (3x3 stride-4 coarse, 5x5 stride-1 fine with prior pre-warp); Shi-Tomasi lambda-min confidence gate
  (idea 1) and pyramid (idea 2) with their thresholds; ring indexing; cumulative backward warp per age; decay weights
  (`pow(decay, age)`, normalised); mix(trail, current, blend); alpha; 4 params and roles; A = (flow*flowScale, |flow|*..., 1)
  raw flow field; depth passthrough; extraBuffer[4] historyHead read.
MECHANISM INTERROGATION:
  tactic 1 (deepen the kernel): the LK window is a flat box (every tap weighs the same), so taps on the far side of a motion boundary
    count as much as the centre — the standard next step is a Gaussian window (smaller effective footprint, sharper motion edges).
  tactic 2 (physics one step further): a real tracker's flow is temporally coherent — objects have inertia; per-frame estimates
    flicker with sensor noise. The first-order side effect a tracker shows is temporal filtering of the velocity along the track.
  tactic 3 (promote an intermediate): `fine.z` (lambda-min) already gates the flow; coarse `lambdaMin` gates the prior. Nothing else is thrown away.
  tactic 6 (history the shader owns): A is the flow field and is written every frame but C is never read. Exactly the history a
    temporal flow filter needs, with the packing already correct (raw flow field, read back raw).
ADD:
  1. Gaussian-weighted LK window — sigma = half/2 (5x5: sigma 1, 3x3: sigma 0.8), weights renormalised to the tap count so lambda-min
     (and the 0.0005/0.01 Shi-Tomasi and 0.002/0.03 coarse thresholds) keep their calibration. Applied to BOTH levels. (§12.1 tactic 1,
     LK's own window weighting.)
  2. Temporal flow carry through C — advect: read C at coord - round(flow) (semi-Lagrangian), undo the stored flowScale, validity
     = C.w, and blend `flow = mix(flow, prevFlow, 0.35)` — Kalman-style velocity inertia along the track; the flat-area gate is
     unchanged so it decays in a few frames. (§12.1 tactic 6; hysteresis through exact `textureLoad(dataTextureC)`.)
FORMULA ADMISSION: both consume quantities the file computes (taps, structure tensor, flow) and the A field it already writes; no new
  state/binding/param; deletion test passes both ways (delete either: still an LK flow tracer; delete LK: not this effect).
FORBID: springs, ripples, pointer anything, IQ palette, colour-wheel overlay, any new param, retuning decay.
A PACKING: raw flow field (A.xy = flow*flowScale in px, A.z = |flow|*flowScale*20, A.w = 1) — unchanged, now also READ back raw with
  exact textureLoad; no ACES on stored fields. Documented in an `A packing:` line (HEAD had none).
RESCUES: metadata — drop the false `mouse-driven` claim from header + JSON `features` (no pointer reads in the file).

---------------------------------------------------------------------------------------------------------------------------
IMPLEMENTATION DELTA (added after the first measurements; the cards above were written first and are unchanged)
- optical-flow-tracer idea 2 (temporal carry) was first built as a plain 35% post-blend of last frame's flow. Measured with
  `forkD_flow.mjs` (moving textured disc, history = previous output like the engine): it lowered jitter but amplified the flow halo
  around movers x1.5 (leak re-fed every frame). Final form: (a) KLT-style INITIALISATION of the fine LK level from C's flow,
  chosen only when it predicts the live pixel better than the spatial prior (hysteresis margin 0.01), plus (b) a 35% inertia
  blend gated to real motion (|prevFlow| 0.5..1.5 px) and by photometric agreement. The Gaussian window is sigma = 0.8*half
  (floor 1.2), not half/2: sigma 1.0 cut the halo -65% but made interior flow +55% noisier; 1.6 keeps interior ~HEAD and still
  cuts static-background false flow ~-28%.
- In the WGSL the new ideas are numbered Idea 3 (Gaussian window) and Idea 4 (temporal carry) because HEAD's two ideas are Idea 1/2.
