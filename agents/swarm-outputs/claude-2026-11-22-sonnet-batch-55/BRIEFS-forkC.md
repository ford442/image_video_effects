# BRIEFS — fork C (mouse-hyperbolic-navigator, breathing-kaleidoscope-morph)

Written before any WGSL edit. HEAD copies + renders in the scratchpad `c/` dir (`*_head.wgsl`, `mh_head_*.png`, `bk_head_*.png`).

## HEAD defects verified (all on HEAD, before editing)

| file | defect | verification |
|---|---|---|
| breathing-kaleidoscope-morph | **Segments slider is dead.** `let segments = max(1.0, u.zoom_params.y)`; the slider is 0..1 so `segments` is always 1 → one 2π "segment", no kaleidoscope. Both 2026-11-10 ideas (mirror-seam bevel "along every reflecting edge", per-segment morph) therefore only ever act on the single atan2 seam. | rendered HEAD at Segments = 0 / 0.5 / 1: **0.00 % of pixels differ** (all three identical, meanL 0.463, meanA 0.051). |
| breathing-kaleidoscope-morph | **`u.zoom_config.x` is read as audio but is TIME** (BINDING_CONTRACT: `.x = time`). `audioReactivity = 1 + 0.3·t` multiplies *absolute time* inside `ping_pong(time·speed·audioReactivity)` → phase = speed·t·(1+0.3t): the breath and the wedge rotation accelerate without bound (rate ×(1+0.6t): ×37 at 1 min, ×181 at 5 min) and there is no audio at all. | analytic from the contract + render pair 50 ms apart: 85 % of pixels change at t=1 s, 99 % at t=60 s. |
| breathing-kaleidoscope-morph | never writes `dataTextureA` although the header documents an A packing. | grep: only `writeTexture` + `writeDepthTexture` stores. |
| breathing-kaleidoscope-morph | `minLuma / maxLuma / centerLuma` are accumulated over every tap (per-tap cost) and never read. | grep. |
| mouse-hyperbolic-navigator | **Möbius `a` leaves the unit disk.** `a = (mouse−0.5)·1.8·navSpeed`, navSpeed 0.2..1.5 → |a| up to 1.08 at the default slider and 1.9 at max; `(z−a)/(1−āz)` is only a disk automorphism for |a|<1, so the picture collapses to one smooth pink blob. | HEAD render, mouse (0.95, 0.95), default sliders: tiling detail gone (panel 3 of `mh_head_sheet.png`); navSpeed 1.0 gives an unrelated spiral. |
| mouse-hyperbolic-navigator | **tileCount is non-integer** (`mix(3,12,p)`, default 7.5) → `fract(angle/2π·N)` does not close across the atan2 cut: a hard seam along −x. | render at default (7.5) vs 8 (slider 0.5556). |
| mouse-hyperbolic-navigator | **mortar is on the wrong line.** `wrapSeam = |fract(a) − 0.5|`, mortar where wrapSeam < 0.02 i.e. fract ≈ 0.5 = the **middle** of each wedge. The image discontinuity (the real tile seam) is where `fract` wraps, wrapSeam = 0.5 — unmortared. | analytic; visible in the N = 8 render: dark rays sit 22.5° off the hard steps, the −x step has no ray. |
| mouse-hyperbolic-navigator | JSON claims `audio-reactive`; the file never reads `plasmaBuffer`. | grep. |
| (checked, not a defect) | ripple waves can drive `color` negative before ACES. | ripple render on a 0.02 source: negative lobes darken (mean Δblue −0.032); 0.9 % of lobe pixels brighten. Added a cheap `max(color,0)` clamp as floor only, **not claimed as a rescue**. |

C is not read by either file and that stays: both are stateless geometric mappings of the *source* frame (a navigator and a kaleidoscope have no history of their own), so the A write is for the downstream slot reading display RGBA. A C read would be the "checklist overlay" §4.1 warns about.

---

## Idea Card — mouse-hyperbolic-navigator

```
SHADER: mouse-hyperbolic-navigator
IDENTITY: the photo wrapped on a Poincaré disk, scrolled by the pointer through a Möbius map,
  repeated in wedges with dark mortar and horocycle gutter rings; Boundary Glow rims it.
KEEP VERBATIM: mobiusDisk / hyperbolicTile / hyperbolicDistOrigin; params (navigationSpeed → a gain,
  tileCount → wedge count, edgeGlow → rim glow + Cauchy R/B split, zoomFactor → disk zoom);
  ring gutters; horo pulse; click hyperbolic ripples; ACES display; A = ACES display RGBA;
  alpha = hDist/3·srcA; depth passthrough.
MECHANISM INTERROGATION:
  tactic 2 (physics one step further): the Poincaré metric is ds = 2|dz|/(1−|z|²). A gutter of
    constant hyperbolic width therefore narrows on screen like (1−r²)/2 and ends as a hairline at
    the rim — the signature of every Circle Limit print. HEAD's mortar has constant ANGULAR width,
    so it fans WIDER toward the rim (the wrong way).
  tactic 3 (promote an intermediate): `fract(angle/2π·N)` and `fract(hDist·…)` throw away the
    integer wedge index and ring index — tile identity, which a tiling has and this file discards.
  tactic 6 (history): not native (stateless navigator) — no C read.
ADD:
  1. Conformal gutter — mortar half-width = k(1−r²)/(2r) in angle (constant hyperbolic width,
     clamped to HEAD's max), measured from the true wedge seam (rescue: the line now sits on the
     discontinuity). The ring gutters were NOT touched: they are already constant in hDist, which
     narrows on screen like (1−r⁴)/2r, i.e. already conformal.
  2. Circle-Limit two-colouring — parity of (wedge index + ring index) of `transformed` tilts the
     tile value ±7 % and hue warm/cool, so adjacent tiles alternate as in an Escher tessellation.
     Uses the integer parts `fract` discarded; tiles stay glued to the navigated lattice.
RESCUES (not ideas): |a| soft-saturated below 0.94 (a·inverseSqrt(1+|a|²/0.94²); first draft used tanh, swapped for
  the rational form to save a transcendental); tileCount rounded to an integer so the wedge pattern closes; mortar moved onto the real
  seam; audio path: bass drifts the Möbius view point (a += dir(0.37t)·bass·0.12, then the same
  saturation) and treble raises the horocycle pulse — makes the `audio-reactive` tag true.
FORMULA ADMISSION: neither idea is a §12.2 row (domain-native: hyperbolic metric, tile colouring);
  both consume quantities the file already has (`transformed`, `wrapSeam`, `hDist`); deleting either
  leaves exactly this navigator; keeping only them is not.
FORBID on this file: springs, orbit-trap reflection folds (that would replace the wedge wrap = a
  new tiling), IQ palette, a second Cauchy use, C read.
A PACKING: ACES display RGBA (unchanged).
```

---

## Idea Card — breathing-kaleidoscope-morph

```
SHADER: breathing-kaleidoscope-morph
IDENTITY: a photo that breathes between plain and a mirror-tube kaleidoscope centred on the
  pointer, each wedge eroded/dilated differently (living crystalline look).
KEEP VERBATIM: params (cycle_speed → breath speed + kernel radius, segments → wedge count,
  rotation_speed → wedge twist speed + gradient boost, breath_depth → max twist); ping_pong
  triangle breath; abs(fract) mirror fold; finalUV = mix(uv, kaleidoUV, blend); disc-in-ellipse
  structuring element around the pointer; erosion/dilation mix by golden-ratio segment hash;
  gradient·0.3; white top-hat re-injection; mirror-seam bevel; alpha = top-hat luma; depth
  passthrough; click ripple displacement.
MECHANISM INTERROGATION:
  tactic 2: a silvered mirror reflects ~90–95 % — a cell seen after k bounces is dimmer and
    slightly tinted by the glass.
  tactic 3: `centerLuma / minLuma / maxLuma` are accumulated in the 81-tap loop and discarded —
    exactly the three numbers a toggle (shock) filter needs.
  tactic 6: not native — no C read (see above).
ADD:
  1. Reflection loss per bounce (§12.2E "fold count as material"): the wedge index modulo N gives
     the cell's fold distance from the primary cell (min(k, N−k)); value ×= ρ^(folds·blend),
     ρ = (0.91, 0.93, 0.955) per channel (cool, silvered-glass tint). Unfolded image (blend 0)
     is untouched; the effect arrives with the breath.
  2. Kramer–Bruckner toggle mapping (domain-native mathematical morphology): per pixel, snap
     toward whichever of erosion / dilation is nearer in luma to the centre sample, using the
     already-accumulated luma extremes; mixed in at ≈0.4 so the per-segment erosion/dilation blend
     stays the base and the cell edges go crisp/crystalline. No extra taps.
RESCUES (not ideas): Segments slider revived (`round(mix(3,12,p))`, default 8) — **changes the
  default picture from "no kaleidoscope" to an 8-wedge one**; `zoom_config.x` (time) removed as
  "audio": breath phase is `time·cycle_speed` again, bass (`plasmaBuffer[0].x`) lifts the breath
  toward the kaleidoscope on beats and treble sharpens the seam bevel (makes `audio-reactive`
  true); wedge index taken mod N so odd N has no cell split at the atan2 cut; write
  `dataTextureA` = the same display RGBA as writeTexture (packing line was a lie by omission).
FORMULA ADMISSION: idea 1 uses the §12.2E fold-count row (C-owned, one file); consumes
  `normalizedAngle`/`segments`/`blend` already computed; idea 2 is not a §12.2 row. Both pass the
  deletion test in both directions.
FORBID on this file: ACES on the photo path (P-ACES: a photo-passthrough filter must not re-grade
  every image; the added light — bevel, top-hat — stays clamped ≥ 0 and is left to the display),
  springs, C read, IQ palette, new params, a second kaleidoscope.
A PACKING: display RGB + top-hat luma in alpha (unchanged), now also stored to A.
```
