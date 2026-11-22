# BRIEFS — fork B (knitted-fabric, lenticular-holographic-shift)

Written before any WGSL edit. HEAD copies in `/tmp/claude-0/…/scratchpad/b/<id>_head.wgsl`.

## Checklist verdicts (COMMON.md "failure checklist", run on both files)

| item | knitted-fabric | lenticular-holographic-shift |
|---|---|---|
| ACES on display, ≥ 0 input | yes (`aces(max(c,0)*0.8)`), ok | yes, `max(col,0)` before ACES, ok |
| plasmaBuffer[0].xyz audio | yes (bass/mid/treble + per-stitch band), ok | yes (bass → shift, mids → moiré, treble → beat), ok |
| C load | none. **Not added** (see below) | none. **Not added** (see below) |
| extraBuffer | no use (comment says so) | **writes [133]/[134] every frame and reads them back → dead, verified (below)** |
| dataTextureB | documented masks (yarn, pull/ridge, shimmer, alpha). B is write-only (binding 8, `texture_storage_2d<…, write>`) and no shader can read it; it is a secondary output. **Kept.** | documented mask quad (strip, moire, viewAngle, alpha). **Kept.** |
| alpha | semantic (yarn coverage) | semantic (holo band) |
| other | none found | none found; `u.config.y` only as the ripple count (legal) |

**Why no `dataTextureC` load on either file.** Both are stateless filters of `readTexture`. A holds display RGBA (the documented chain contract: "chained slots read C (= prev A) expecting colour"), so there is no non-colour channel to carry a memory in without breaking A packing (alpha is semantic, B is write-only). The only native memory idea (yarn that stays stretched and relaxes; a lenticule that latches) would need a scalar state texel. Adding a C read to satisfy a checklist would be exactly the generic-overlay/hygiene move of §4. The A write stays: downstream slots consume it as display RGBA.

## lenticular-holographic-shift — HEAD defect verified

`extraBuffer[133]/[134]` is the "critically-damped view spring". The engine (and the harness, `mr.mjs:141`) zero `[133..255]` before every dispatch, so each invocation reads `viewPos = 0`; the only non-zero value is whatever gid(0,0)'s workgroup has already written in the same dispatch (a data race: `0 + k²·(mx−0)·dt·dt = 0.0256·mx`). Result: `viewAngle ≈ −0.8 + sin drift` for every mouse x. Measured with mouse x = 0.1 / 0.5 / 0.9 at HEAD (256 px, 20 frames): 53 % / 53 % / 68 % of pixels differ by > 8/255 — but only from the race's ≤ 0.026 phase nudge (intended swing is ±0.64 viewAngle ≈ 0.9 strip). Mouse.x does not steer the print. **Rescue: stateless `viewPos = mouse.x`** (raw pointer, same as knitted-fabric's 2026-10-27 lesson); the spring smoothing cannot persist without state and is dropped, comment updated. **Default look changes**: at mouse 0.5 the baked `−0.8` view offset disappears (viewAngle ≈ drift only) — numbers in NOTES.

---

## SHADER: knitted-fabric

IDENTITY: the photo re-knitted as a yarn stitch grid (V-loops, purl rows), pulled by the cursor, plucked by click waves; the colour of each stitch is the photo sampled at its centre.

KEEP VERBATIM: 4 params and roles (StitchSize → stitchScale, PullStrength, PullRadius, TextureDepth → gap shadow / shimmer / depth mix); `distortedUV` pull + click pluck waves; stitch lattice (`st`, odd-row half offset, `cellId`, `local`, `loopArc`/`underArc`); strain-thinned yarn; purl rows; two-ply twist; heather + flecks; per-stitch band shimmer; lint; ACES `aces(max(c,0)*0.8)`; A = ACES display RGBA; B = (yarnMask, max(pull, clickRidge), shimmer, alpha).

MECHANISM INTERROGATION
- tactic 1 (deepen the kernel): the yarn is a distance-field ribbon (`smoothstep(w, 0, |local.y − arc|)`). Next-better approximation of the same operator: a *tube*. The ribbon already carries the across-yarn offset (`across`) but only uses it for the twist stripes.
- tactic 2 (physics one step further): a lit yarn tube is bright on the lit flank and dark on the other, and the loop lying over the under-yarn shades it. Nothing in HEAD is directional: `shadow`, `gapMask` and `plyShade` are all symmetric.
- tactic 3 (promote an intermediate): `across` (signed distance across the dominant yarn) and `loopArc` are computed and discarded after the twist. The top-loop arc is also exactly what is needed to cast a shadow of the loop: re-evaluate it at a light-shifted `local`.
- tactic 6 (history): see above — no native C idea fits the A packing; not added.

ADD (2 native ideas):
1. **Round-yarn tube shading + fibre sheen.** `across / halfWidth` → tube normal `(0, a, √(1−a²))`; half-Lambert from an upper-left light across the tube (lit flank / shaded flank), plus a Fresnel–Schlick rim `0.04 + 0.96·(1−n.z)⁵` tinted by the stitch's own colour (fabric sheen at grazing flanks). Replaces nothing: multiplies `finalColor` on yarn texels only, `yarnMask`-weighted; photo colour (`baseColor`) stays the albedo.
2. **Loop cast shadow.** The top loop's arc re-evaluated at `local − lightShift` gives the soft shadow it throws onto the under-yarn and the backing; amount rides the existing TextureDepth slider (it already means "how deep the fabric reads"). Masked out of the top yarn itself.

FORMULA ADMISSION: Idea 1 uses §12.2F *Fresnel–Schlick* (B owns it, knitted only). Family-match sentence: a yarn is a lit dielectric cylinder; textile sheen *is* its grazing-angle reflectance, so the row's "grazing reflectance, one term" is native to the tube, not an optical costume. Consumes `across` and `yarnWidth`, both already computed. Deletion test: removing it leaves the ribbon knit exactly as HEAD; keeping it alone is a lit tube, not a different effect. Idea 2 is a domain mechanism (no §12.2 row): consumes `loopArc`/`topYarn`/`yarnWidth`; deletion leaves HEAD.

FORBID on this file: springs, click shockwaves beyond the existing pluck, IQ palette, holographic scan, any new param, any change to `stitchScale`/pull math, replacing the ribbon masks, a C read.
A PACKING: unchanged — ACES display RGBA in A; B masks unchanged (yarnMask, max(pull, clickRidge), shimmer, alpha).

---

## SHADER: lenticular-holographic-shift

IDENTITY: a holographic lenticular print: vertical lenticules whose perspective and colour shift as you rock the view (mouse x), with audio-beat moiré and click flashes.

KEEP VERBATIM: 4 params and roles (Shift → strip + chromatic shift amount, Frequency → strips across, Color → holo hue offset, Beat → moiré pulse); `strip`/`band`; R/G/B view offsets; depth parallax per lens (Idea 1 of 2026-11-10); moiré + holo cycling; click flash rings; cylindrical ridge specular; vignette; print grain; ACES; A = display RGBA; B = (strip, moire, viewAngle, semantic alpha); vertical tilt from mouse.y; `sin(time·0.3)·0.1` idle sway.

RESCUE: dead view spring → `viewPos = mouse.x` (see above).

MECHANISM INTERROGATION
- tactic 1 (kernel): the print = N interlaced views behind a cylinder-lens array. HEAD models the *selection* (strip phase, one parallax-shifted sample inside the lenticule) but treats each lenticule as a flat window. Next-better: what a lenticule does optically (magnifies its own slice) and what a print technician names as the defining defect (adjacent-view crosstalk).
- tactic 2 (physics): lens magnification across each cylinder; ghosting of the neighbouring view where the interlaced columns spill past the lens focal width.
- tactic 3 (promote an intermediate): `strip` (fract phase 0..1 inside the lenticule), `lensX = strip·2−1` and `sceneDepth` are computed; `lensX` only feeds the specular, `strip` only feeds `band`/moiré. Both are exactly the inputs the two ideas need.
- tactic 6 (history): see above — none.

ADD (2 native ideas):
1. **Cylinder-lens magnification.** Each lenticule magnifies its own slice: the base R/G/B samples are displaced horizontally by `lensX · lensK / freq` (barrel compression toward the lenticule centre, scaled by the Shift role through `shiftAmt`, 0 at Shift 0), so the picture reads as vertical slivers, each locally magnified, instead of a flat window. Chromatic view offsets stay on top.
2. **Adjacent-view crosstalk ghost.** On the seam side of each lenticule (`|lensX|` → 1) the neighbouring view bleeds in: one extra parallax sample at `viewAngle ± 1/N` (N = 8 views) weighted by `smoothstep(0.45, 1.0, |lensX|)`, signed by which seam the pixel is near. Reuses `sceneDepth`; the ghost's offset grows with depth contrast like the main parallax.

FORMULA ADMISSION: neither idea is a §12.2 row (domain mechanisms; no ownership needed). Both consume `strip`/`lensX`/`sceneDepth`/`viewAngle` already computed. Deletion test: removing either leaves HEAD; keeping either alone is still a lenticular print (a lenticular technician names both: lens magnification and ghosting/crosstalk). Expert test passes.

FORBID on this file: new springs, ripple fronts beyond the existing click flash, IQ palette, new params, thin-film, a C read, Fresnel (owned by knitted-fabric in this fork), Cauchy (E owns it).
A PACKING: unchanged — display RGBA in A (ACES colour, semantic alpha); B quad unchanged (viewAngle now = the rescued stateless value).
