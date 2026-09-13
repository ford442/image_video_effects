# NOTES — claude-2026-09-13 gen mid/high ten

---

## gen-fractal-clockwork

- Kept verbatim: sdGear, parity-alternating cell map, 96-step raymarch, shade() material thresholds, four slider roles, sprung orbit camera (extraBuffer[133..138]), click-torque rings, ideas 1–2, chromatic dispersion, C blend, alpha/depth logic. JSON `params`/`updatedParams` byte-exact.
- A packing: ACES display RGBA in A; C read with exact `textureLoad` as colour history (unchanged).
- Idea locations (public/shaders/gen-fractal-clockwork.wgsl): Idea 3 escapement offset in map() L64, tick phase/esc/tickFlash computed in main L142–148 and passed through raymarch/normals/tGear, tick flash L193–194; Idea 4 ruby jewel ring + glint L195–201. Existing ideas 1–2 at L185/L189.
- Escapement step = pi/teeth (exactly one tooth period of the sin tooth profile), so `fract()` wraps seamlessly with no float growth; gated by rotation-speed slider so speed 0 still means stopped.
- Floor: audio was already plasmaBuffer[0].xyz and ACES already present; banner Features was dishonest — now lists audio-reactive, upgraded-rgba. JSON features gained "audio-reactive" and "mouse-driven" (orbit camera follows pointer). No dead sliders, no hardcoded alpha, no reserved identifiers found.
- Gates: naga "Validation successful"; wgsl_precommit_gate --files 1/1 passed, 0 extraBuffer violations; no textureStore(dataTextureC.
- Real-GPU visual QA: external.

---

## gen-fractal-ember-lattice

- Kept verbatim: triLatticeDist3 kernel, ember palette + hot-ramp chain, shard state machine (explosion/rotation/decay/reform), boundary glow, chromatic shard separation, motion streak, treble sparks, alpha formula, CA/ACES/composite, all four slider roles. Saved `params` byte-exact (only `features` + description changed in JSON).
- A packing: unchanged raw shard state (A.rg displacement, A.b seed, A.a reform), C read via exact `textureLoad(dataTextureC, coord, 0)`; no tone-map on stored fields.
- Idea locations (public/shaders/gen-fractal-ember-lattice.wgsl): Ideas 1–2 existing (~L158–164); Idea 4 cooling factor + reignite ~L172–177 (applied to `hot` L177 and junction glow L183); Idea 3 heat crawl ~L185–199 (Spark Density scales bead amplitude, bass speeds crawl); Idea 4 colour shift + re-ignition flash ~L201–203.
- Floor: already compliant (13 bindings, 16x16, plasmaBuffer[0].xyz audio, ACES on display, semantic alpha, depth write, A-only). Fixes: header normalized (single Upgraded 2026-09-13, full Ideas list, honest A packing); JSON features gained "audio-reactive" and "mouse-driven" (both true).
- Gates: naga "Validation successful"; wgsl_precommit_gate 1/1 pass, 0 extraBuffer violations. No textureStore(dataTextureC. No GPU visual QA.

---

## gen-fractured-monolith

- Kept verbatim: raymarch loop/limits, map() SDF (floor wave, base box, 1.5 cell fracture, drift, per-cell rotation, crack carve), crack glow formula (now multiplied by pulse factor), mouse orbit camera, floor reflection, Ideas 1–2, vignette, C max-feedback, ACES, alpha/depth, all param roles. JSON `params`/`updatedParams` byte-exact.
- A packing: ACES display RGBA in A and writeTexture; C read with exact `textureLoad` as color history (unchanged).
- Idea locations (public/shaders/gen-fractured-monolith.wgsl): Idea 3 seam light pool L246–263 (floor branch of main; Fracture Spread widens footprint/seams, Glow Intensity scales, bob/Rotation Speed shape it, treble lifts); Idea 4 rising seam pulse L153–158 (map() glow; Levitation Speed paces it, bass brightens). Ideas 1–2 L267–274.
- Floor fixes: standard 9-line banner (Features/Upgraded/Ideas/A packing); renamed noise() local `u` that shadowed the `u` uniform to `w`; `var` -> `let` for immutable locals. Audio already plasmaBuffer[0].xyz, alpha semantic, depth written, no extraBuffer/dataTextureB use. JSON features gained "audio-reactive", "mouse-driven" (mouse orbits camera); description refreshed.
- Perf: no new loops; pool is ~15 scalar ops on floor hits only, pulse is 3 ops per map() call.
- Gates: naga "Validation successful"; wgsl_precommit_gate 1/1 pass, 0 extraBuffer violations. No `textureStore(dataTextureC`. No GPU visual QA.

---

## gen-ghost-flame

- Kept verbatim: noise/fbm kernel, velocityField, advection/diffusion/vorticity, combustion, height cooling, base fuel feed, Ideas 1-2 (wick, chemiluminescence), mouse heat + ripple bursts, palette/glow/smoke/age tint, soft tone map + CA + ACES, alpha curve, slider roles, saved params (JSON params byte-exact), extraBuffer[133..134] envelopes.
- A packing: unchanged raw sim state (temperature, fuel, velocityX, age); C read only via exact textureLoad; ACES only on writeTexture; no textureStore(dataTextureC).
- Idea 3 (buoyant puffing pinch-off): public/shaders/gen-ghost-flame.wgsl L256-263, right after height cooling. Travelling sin^6 cooling wave along +y (advection direction), snoise3 phase wobble, mids speed it up, Flame Height scales neck depth, RMS deepens it.
- Idea 4 (schlieren heat haze): L307-313 (gradient from existing left/right/up/down C taps, resolution-normalized, fringes in cool air, Diffusion scales strength, treble brightens), alpha gains haze*0.12 (L~334), depth thermal relief L357-359.
- Floor fixes: depth was a pass-through of input depth; now a truthful thermal relief. JSON features gained "audio-reactive" (plasmaBuffer[0] drives height/turbulence/puffs/haze) and "mouse-driven" (pointer heat source). Audio source, semantic alpha, ACES, 13 bindings, 16x16 already correct; all 4 sliders live; resolution division guarded with max(res.y,1).
- Gates: naga "Validation successful"; wgsl_precommit_gate --files 1/1 passed, 0 extraBuffer violations. No GPU visual QA.
- Pre-existing quirk left alone: base fuel feed uses uv.y<0.15 while first-frame seed sits at uv.y=0.92 (identity-preserving; not changed).

---

## gen-hopf-fibration-fiber-bundle

- Kept verbatim: Hopf lift, stereographic projection, rz 4D rotation, 40x32 segment loop, hue mapping (hoisted out of the inner loop, same values), crossingInt bloom, treble specks, click phase-fronts, C blend, alpha formula, all four param roles. Params byte-exact.
- A packing: ACES display RGBA in writeTexture and dataTextureA; C read via textureLoad(dataTextureC, coord, 0).
- Idea 1 (over/under gaps): WGSL lines 84-89 (slots), 182-195 (front selection + gap cut; gap depth scales with Crossing Bloom).
- Idea 2 (U(1) beads): line 164-167 (speed from Particle Drift, brightness from bass).
- Idea 3 (S2 inset): lines 90-98 (placement), 119-131 (base-point dots, rotated by rot4D, pointer via s2phi/s2theta), 197-207 (limb + alpha/depth coverage).
- Floor fixes: guarded z1r (max 0.001) and depth4 denominator (max 0.05) against div-by-zero; JSON gained "upgraded-rgba"; header Upgraded 2026-09-13 + Ideas/A packing lines. Audio already plasmaBuffer[0].xyz, ACES/alpha/depth/A already correct.
- Gates: naga "Validation successful"; wgsl_precommit_gate 1/1 pass, 0 extraBuffer violations; plasmaBuffer[ count 3; no textureStore(dataTextureC).
- Real-GPU visual QA: external.

---

## gen-hyper-rainbow-vortex

- Kept verbatim: all 4 spiral layers, palettes, Rankine swirl constants, mouse secondary vortex, click fronts, core glow/bands/pulse, Ideas 1-2, chromatic offset, ACES, alpha formula, param roles. Saved `params` byte-exact.
- A packing: raw HDR display RGBA history (pre-ACES) in A, read back from C via exact textureLoad (now at pixel + back-rotated pixel); alpha = vortex energy.
- Idea locations (public/shaders/gen-hyper-rainbow-vortex.wgsl): Idea 1 L187, Idea 2 L190, Idea 3 L223-233 (advected C fetch, 65% mix with in-place history), Idea 4 L193-201 (condensation haze) + L249 (depth funnel).
- Floor fixes: guarded aspect division (max(res.y,1)); header normalized to `Upgraded: 2026-09-13` with all four ideas; JSON features add "mouse-driven" (pointer steers vortex center + secondary vortex), description refreshed. Audio already plasmaBuffer[0].xyz; no extraBuffer use; no dataTextureC writes. All four sliders live (speed also scales advection step; scale sets funnel striae count; intensity lowers dew point).
- Gates: naga "Validation successful"; wgsl_precommit_gate 1/1 pass, 0 extraBuffer violations. No real-GPU visual QA.

---

## gen-hyper-refractive-rain-matrix

- Kept verbatim: map() capsule lattice + 3x3 smin merge, pointer repulsion, 100-step march, calcNormal, cosine/blackbody OkLab sky, Fresnel rim, caustics, fog, click caustic rings, temporal blend weights, ACES on display, depth write, all four param roles. JSON `params` byte-exact.
- A packing: raw HDR RGB + coverage alpha, unchanged; C read raw via exact textureLoad (now two taps); no textureStore to C; no extraBuffer use.
- Idea 1 (lightning): `lightningFlash()` line 89; sky flood line 187; rim back-light line 226. Driven by Storm Intensity (rate, chance, brightness) and bass (trigger chance).
- Idea 2 (dispersion): line 203 — R/B refract at eta -/+ disp (disp from Fluid Viscosity + mids), per-channel palette weighted by rim angle.
- Idea 3 (streaks): line 270 — history pulled from pixel.y + streakLen (1..10 px by Drop Speed, + bass), mixed 0.7 with in-place history.
- Floor fixes: Fresnel `pow(1+dot(rd,n),4)` base clamped to [0,1] (negative base -> NaN); header rewritten to §8 banner; JSON features + "mouse-driven" (pointer repels drops), "upgraded-rgba"; description now honest (previous "storm flashes" did not exist in code).
- Gates: naga "Validation successful"; wgsl_precommit_gate 1/1 pass, 0 extraBuffer violations. No real-GPU visual QA.

---

## gen-hyper-warp

- Kept verbatim: rand/noise/fbm kernel + octave counts, q -> r -> val chain, both palettes and blend, radial burst, Ideas 1-2, stabilizeHistory + cold-start seed, opacity/CA/vignette, slider roles, saved params (JSON params byte-exact; only description refreshed).
- A packing: unchanged raw HDR history RGBA (A.rgb = pre-ACES chromatic vignetted color clamped [0,6], A.a = coverage). C read via exact textureLoad only; no textureStore(dataTextureC).
- Idea 3 (warped level-set etching): public/shaders/gen_hyper_warp.wgsl ~L205-215, after Idea 2. Scale -> isoline count, Intensity -> etch depth, stretch -> line width, fold/mid -> lip highlight.
- Idea 4 (flow-dispersed feedback): ~L169-182, per-channel exact loads at flowVec -/+ flowDir * dispersePx (flow speed + bass widen). Card draft said 0.7x/1.3x scaling; changed to an additive pixel offset because scaling a 1-4px flow rounds away to nothing.
- Floor fixes: removed duplicate `Upgraded:` lines (single 2026-09-13); renamed noise() local `u` that shadowed the uniform; guarded aspect division with max(resolution.y, 1.0). Audio already plasmaBuffer[0].xyz; alpha already semantic; ACES on display only; all 4 sliders live.
- Gates: naga "Validation successful"; wgsl_precommit_gate --files: 1/1 passed, 0 extraBuffer violations. No GPU visual QA.

---

## gen-hyperbolic-crystal-symbiosis

- Kept verbatim: hash fns, Mobius translate, hyperbolicDist, hyperbolicTiling, crystalFacet seed loop (only return widened to a `Facet` struct adding secondId/minK), jewelColor, ACES helper, mouse focus, audio curvature, front wave / edge glow / tiling edge / growth front / click fronts, vignette, drifting exact-C history, base alpha/coverage formulas, slider roles. Saved `params` byte-exact.
- A packing: raw HDR display-history RGBA (pre-ACES temporal rgb clamped [0,6.5], coverage alpha); C read via exact textureLoad at drifted coord. Unchanged.
- Idea locations (WGSL): Facet struct fields 124-125; Idea 1 growth zoning ~243-253; Idea 2 twin lamellae ~255-263; Idea 3 hyperboloid lift relief ~299-306 (depth blend at ~320). Single write set at 326-328.
- Floor fixes: the "two textureStore(dataTextureA / writeDepthTexture" were an early-return outside-disk path plus the main path — restructured into one var-based branch with a single write set at the end (outside-disk values unchanged: rgb (0.05,0.04,0.08), alpha 0.08, depth 0.02). Removed unused `q` local (inlined 4.0, function ignores it). Mutation slider was nearly invisible (seed radius wobble only) — now also drives zone-spacing jitter and zoning strength. Standard banner added. JSON: +upgraded-rgba, description refreshed. Audio already plasmaBuffer[0].xyz; ACES already on display; alpha already semantic.
- Gates: naga "Validation successful"; wgsl_precommit_gate 1/1 pass, 0 extraBuffer violations. No textureStore(dataTextureC. No real-GPU visual QA.

---

## gen-hyperbolic-tessellation

- Kept verbatim: bindings, Mobius drift/held-mouse translation, rotation, 8-step angular fold recursion, palette/tilePulse/boundary/vertex glow, horocycle rings, click ripples, C feedback blend, all 4 params (JSON params byte-exact).
- A packing: unchanged — raw HDR RGB + coverage in A, C read via exact textureLoad; ACES only on writeTexture.
- Idea locations (WGSL): Idea 1 line 94, Idea 2 line 113, Idea 3 lines 119-148 (symmetry slider sets p; Boundary Glow boosts geodesic brightness), Idea 4 lines 150-154 (Depth Color sets parity strength); geodesic/parity also feed coverage (170) and depth (171).
- Floor: already present (13 bindings, 16x16, ACES, semantic alpha, plasmaBuffer audio, depth, A write, no extraBuffer). Only fix: non-standard header normalized to 7-line banner. JSON features gained "mouse-driven" (held mouse translates the disk).
- Gates: naga "Validation successful"; wgsl_precommit_gate 1/1 passed, 0 extraBuffer violations. No textureStore(dataTextureC. Real-GPU visual QA: external.
