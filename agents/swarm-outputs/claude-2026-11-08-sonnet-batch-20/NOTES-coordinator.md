# sonnet/batch-20 — coordinator notes (topological-acoustic-knots, acoustic-string-theory, gen-string-theory, gen-audio-spirograph)

Forks A / B notes: NOTES-forkA.md / NOTES-forkB.md. Cards: BRIEFS-coordinator.md. Independent review: REVIEW.md.
Renders: agents/minirender.mjs 192–512 px, JSON-default sliders passed explicitly, audio (0.3,0.2,0.1) unless stated, mouse (0.5,0.5) up. `agents/minirender_rip.mjs` (RIPPLE=x,y,tStart) injects one click ripple. SwiftShader only — **real-GPU visual QA is external.**

State-texel scheme (acoustic-string-theory, gen-string-theory, gen-audio-spirograph): extraBuffer[133..255] is overwritten with zeros every frame by `writeExtraBuffer` (the whole 256-float scratch is uploaded), so the springs these three files advertised never persisted. Spring pos/vel now live in A texel (0,0), `(fract(lastTime),-,-,0.7371)` in A texel (1,0) — **`fract(time)`, not absolute time, because A is rgba16float on the balanced/battery/auto tiers** (REVIEW #2: a half float has a 0.25 s step at t≈300 s, which made dt noise); `dt = clamp(fract(time - st1.x), 0.001, 0.05)`. The sentinel guards the first frame and an inherited C; the trail read is zeroed on those two texels; every thread integrates the same step from the same C texels, so all agree. (spirograph: top-left corner; the vignette there is ~0.2–0.4, not 0, so those two texels just lose their trail, invisibly.)

---

## topological-acoustic-knots (1st pass; RESCUE)
Pre-state: pure black with any audio ≥ 0.1 (meanA 0.004 @0.1, 0 @0.3+); a grey slab with scribble in silence. Cause: `S = relaxS − |disorder|` subtracts an absolute bass term every frame against a 3 %/frame relaxation → S pinned at 0 for bass > ~0.08, and alpha ∝ S.
| case | HEAD meanL / meanA (192 px, 90 f) | now meanL / meanA (384 px, 100 f) |
|---|---|---|
| silence | 0.227 / 0.438 | 0.181 / 0.468 |
| audio 0.3,0.2,0.1 | 0 / 0 | 0.125 / 0.389 |
| audio 0.8,0.6,0.4 | 0 / 0 | 0.109 / 0.210 (dim film by design) |
**Kept verbatim:** 4 params and roles; Q = (Qxx, Qxy, S, defect) raw in A; trefoilSDF; phonon; homeotropic anchor; ripple loops; annihilation (opposite-sign pair melts the core); red/blue core colours; +1 bloom; chromatic aberration; ACES display; alpha and depth formulas.
**A packing:** raw sim state, never tone-mapped (unchanged).
**Rescues (floor, not ideas):** S melt as a fractional, super-linear-in-bass rate; exact textureLoad reads (HEAD sampled C with the filtering sampler at texel corners = half-texel drift + blur) and a true Q→angle decode (HEAD read Qxx as an angle); true 8-point plaquette winding (±½ blue / ±1 red now mean what they say); stateless polarizer sweep and a local annihilation flash (extraBuffer[135/136] never persisted); ripple age on one clock; mouse-anchor blend clamped to ≤ 1 (at p4≈1 it was 2.4 → overshoot diverged); bounds guard + centred uv; resolution-scaled nucleation cells and winding radius.
**Ideas (idea → line in the file):** 1 crossed-polarizer brushes (sin²(2(θ−φ)): 2 per ±½ core, 4 per ±1) → `// ── Idea 1` L224; 2 Michel–Lévy retardance tint, Δn ∝ S, trefoil thickness wedge → L234; 3 Kibble–Zurek quench ∝ (1−S)⁴ toward a *random smooth Q-field* (two `vnoise` octaves at uv·9 → `noiseAngle = ½·atan2(qb,qa)`; relaxation by `wrapHalfPi`) → L142. First drafts used a per-block hash (REVIEW #1: a fixed block lattice → rectilinear brushes and hundreds of corner "defects" at ≥512 px); the smooth field is resolution-stable (checked at 192 / 384 / 576 px). Verified visually: silence shows the coloured fringes + trefoil contours; a held pointer at (0.35,0.5) gives a radial +1 aster with the 4-brush cross (v5_pin_zoom.png).
**Formulas:** none from §12.2 (tactic-derived).
**Not verified / open:** real-GPU look and cost (≈40 texel loads per pixel: 4+4 relax, 3×8 winding, 9 halo); the initial-quench defect density depends on the 1/36-height nucleation cells; f16 data textures in the app (minirender uses f32) — angle decode precision is fine at S ≥ 0.1 but a melted core (S→0) decodes noise by construction; loud bass (0.8) leaves a dim, speckled film by design (S* ≈ 0.3).

## acoustic-string-theory (1st pass; RESCUE of the 2026-07-22 interactive pass)
| | HEAD | now |
|---|---|---|
| idle default (256 px, 40 f) meanL / stdL / meanA | 0.385 / 0.305 / 0.48 | 0.413 / 0.299 / 0.485 (pins only; pins disabled → byte-identical to HEAD, mean diff 0.0) |
| click 0.3 s ago, diff vs idle (mean abs, 0–255) | n/a (plucks never fired) | 18.7 @0.15 s, 6.1 @0.5 s |
| sympathetic ablated / glide ablated (click on string 0, 0.3 s) | – | 10.4 / 9.0 |
**Kept verbatim:** 4 params and roles; string and harmonic contour construction; bandWeight spectrum drive; bass envelope; node glints + treble sparkle; well constants (42 / 7); click shock ring; pluck gaussian and decay constant; luma boost; ACES; alpha/depth; A = (bass env, harmonicField, nodeField, alpha).
**A packing:** as HEAD + state texels (0,0), (1,0); bass envelope read from texel (2,0). Noted, not changed: C.rgb = (bass, harmonicField, nodeField) is mixed into the colour as a 3–4.5 % trail.
**Rescues:** spring well and pluck state were in extraBuffer[133..141] (zeroed every frame) → the well sat at (0,0), `pluckAmp` ≡ 0, the click shock was centred at (0,0); `dt` was `config.y` (the ripple count) → now from the stored time; pluck = newest ripple in `u.ripples` (stateless); `normalize` of a zero vector guarded.
**Ideas:** 1 sympathetic resonance (pitch ratios 2:1, 3:2, 4:3, 5:4, 5:3 … of `2+0.5·i`; swells in, broad gaussian) → L172; 2 tension-modulation pitch glide (closed-form chirp `age + g(1−e^{−k·age})/k`) → L147; 3 standing-wave nodal pins (zeros of sin(k_i x)) → L206. Ideas 1 and 2 act after a click; only 3 is idle-visible.
**Not verified:** click behaviour on the real ripple buffer (minirender injects one ripple; a real click spawns one per press, ripples expire after their lifetime so the pluck falls silent when the newest ripple is gone — by then pluckEnv ≈ 0); real-GPU look.

## gen-string-theory (2nd pass)
| | HEAD | now |
|---|---|---|
| 256 px, 24 f, sliders 0.5 ×4 | meanL 0.209 / stdL 0.21 / meanA 0.049 | 0.268 / 0.212 / 0.049 |
**Kept verbatim:** the 4 params and roles; partial series with HEAD's inharmonicity; bridge-reflection pluck; hue table; core + glow + sin(dist) ripple; chromatic aberration; background overlays; click shells; trail; ACES; A = display RGBA.
**A packing:** display RGBA + state texels (0,0), (1,0).
**Rescue:** sprung cursor state (see above); **JSON had no top-level `params`** (only x-meta), so the app showed no sliders and fed 0.5 ×4 — added `params` mirroring `x-meta.upgrade.params`. **Behaviour change:** default is now (0.5, 0.6, 0.85, 0.5) instead of 0.5 ×4 (richer partials, longer damping).
**Ideas (file numbering continues HEAD's 1–2):** 3 Melde long-exposure envelope with arcsine dwell (root-sum-square of the standing-partial amplitudes; first draft summed peaks and flooded the frame) → L71 / L102; 4 fretting finger (held pointer pins a node; each side re-fitted as a shorter, higher string) → L49. Verified: the soft lens-shaped ghost is visible around each string; pressing at (0.5,0.46) pinches the nearest string.
**Open:** the fret pin width (0.03 of the string) and the 0.022 ghost gain are judged on SwiftShader at 256 px.

## Post-review changes (all applied; REVIEW.md numbering)
- #1 topological quench noise → smooth random Q-field (above). #2 `fract(time)` in the state texel on acoustic-string-theory, gen-string-theory, gen-audio-spirograph. #3 gen-acid-lissajous `SAMPLES` 96 → 64 (visually identical; frame time −24% on SwiftShader; the 12-chord refinement covers the coarser chord).
- #4 gen-string-theory: `tFac` removed from `cos(w·t·tFac)` (the fret pin keeps the spatial remap `xS`, so a shorter segment still has higher pitch; dragging no longer re-phases every partial with session time).
- #6 acoustic-string-theory: the six `exp(-pow(neg, 2.0))` sites → `exp(-sq(x))` (WGSL leaves pow with a negative base undefined). #7 spirograph header comment + teeth cap. #8 stellar Doppler tint boosted to `max(vec3(1−0.9v, 1−0.3|v|, 1+1.8v), 0.15)` (ablation mean diff 1.26 → 2.13 / 255; still the subtlest of the three stellar ideas, by design).
- #10 gen-quantum-resonance-lattice: camera moved off the node column, `ro = (0.37, 0.29, z)` — a **pre-existing floor bug rescue** (t = 2.1 s was a flat slab, t = 6.3 s a bright slab, ~1 in 18 times at defaults; new: meanL 0.231 / 0.373 with normal contrast; t = 4.0 ≈ unchanged 0.111 → 0.102).
- #5 / #9 kept as disclosed (resonator exposure constants; gen-string-theory `params` added).
- Not changed, pre-existing: gen-acid-lissajous spring still in extraBuffer[133..138] (re-initialised from the raw mouse every frame).

## gen-audio-spirograph (2nd pass)
| | HEAD | now |
|---|---|---|
| 256 px, 24 f, (0.5,0.6,0.7,0.3) | meanL 0.307 / stdL 0.31 / meanA 0.152 | 0.29 / 0.298 / 0.148 |
**Kept verbatim:** 4 params and roles; epi/hypotrochoid parameterisations and per-curve R, r, d; 12/10-segment sweep; additive gear glow; hubs; stator ghost; cusp flash; click chime; geo ring; history accumulation; vignette; A = history RGB + coverage.
**A packing:** unchanged + state texels (0,0), (1,0) (far corner, outside the vignette).
**Rescue:** sprung lens state (see above).
**Ideas (file numbering continues HEAD's 1–3):** 5 rolling gear + pen arm (ring about the hub, arm hub→pen, pen dot, five epitrochoids) → L191; 6 no-slip gear teeth (gear teeth locked to the arm angle; stator teeth count = N·R/r) → L168; 7 ink pooling by pen speed (nearest-segment length vs the curve's mean) → L164 / L240. The mechanism is faint at defaults (the large gear sits near the vignette and the bright polyline curves); it reads best at low Trail Length. Teeth meshing is aesthetic, not phase-exact (non-integer R/r).
Stator teeth count is capped at ~4 px pitch (`minRes`), because uncapped it reached ~165 teeth and aliased to a dither at 384 px (REVIEW #7).
**Cost:** SwiftShader frame time ~1.3–1.5× HEAD at 256 px.
