# BRIEFS — fork A (ink pair): ink_dispersion_alpha, ink-dispersion-guided

Written BEFORE any WGSL edit. HEAD copies: `/tmp/claude-0/-root-image-video-effects/741dbe8f-87a6-4dc9-8039-cfc9fd9fdfde/scratchpad/a/<id>_head.wgsl`.

## Coordinator facts, verified by reading HEAD

- `ink_dispersion_alpha` really is **stateless**: no `dataTextureC` load, no velocity field, no advection, mouse is only a darkening vignette. JSON `features` `fluid-sim, curl-noise, advection, mouse-spawn` and the "Navier-Stokes" description are false for the code.
- Neither file claims `audio-reactive` (JSON) or reads `plasmaBuffer` → no audio defect; adding audio is not native to a halftone (not done). Neither writes B. Neither uses ACES; both are photo passthrough → P-ACES policy: no ACES, no `upgraded-rgba` tag (the files never carried it).
- Host copies A→C only when some enabled shader samples C (BINDING_CONTRACT feedback copy order) → a C read enables the copy; C = this slot's previous display RGBA (A is display RGBA, so the read matches the packing).
- Extra HEAD findings in `ink-dispersion-guided`: `rippleCount = u32(u.config.y)` unclamped (u.ripples has 50 slots); output `finalColor * depthBoost` (up to ×1.3) unclamped; `paper_tex = 0.95 + 0.05*hash12_((uv*time)*0.001 + 100)` is a *time-scaled* hash, not paper tooth: smooth low-frequency blotches at t≈1 s (mean neighbour diff 0.004), decorrelating into per-pixel flicker noise by t≈200 s (0.40) — verified numerically with a Python port of hash12_.

---

## SHADER: ink_dispersion_alpha
IDENTITY: a photo re-inked as a posterised halftone — Sobel ink outlines plus luma-sized dots with paper-fibre granulation, coffee-ring rims and noise-wet dot edges; alpha is ink coverage.
KEEP VERBATIM: 4 params and their HEAD roles (p1 dot pitch, p2 edge threshold, p3 posterise levels, p4 ink density — JSON names Diffusion/Viscosity/Intensity/Reaction stay byte-exact); Sobel hypot edge; `floor(src*levels)` posterise; analytic dot with wet-bleed warp; the two-octave `fibre` granulation (0.6/0.4 mix); coffee-ring rim; alpha floor `mix(0.15,0.45,…)`; mouse vignette; depth write of ink alpha; A = display RGBA (ink colour, ink coverage).
MECHANISM INTERROGATION:
- tactic 1 (next-better approximation): HEAD's "wet bleed" is a *static* noise warp of the dot boundary. The next approximation of ink spreading is bleeding through time — an iterated, damped diffusion of what is already on the paper, i.e. a read of C.
- tactic 2 (physics one step further): ink on paper wicks along the fibres (capillarity), and the dyes in a coloured ink separate as the front moves (chromatography): the colour fringe runs ahead of the dark pigment.
- tactic 3 (promote an intermediate): the two crossed fibre octaves are computed for granulation and then summed away; their orientation (octave 1 is long in y, octave 2 long in x) is exactly the wicking direction field.
- tactic 6 (history the shader owns): C is unread today. A = display RGBA → read C as colour+coverage with an exact `textureLoad`, write A with the same meaning. No new channel, no packing change. Contraction (fresh source mixed in each frame, weights < 1) keeps a still image stable; C=0 on frame 1 is harmless (halo weight is gated by neighbours being darker).
ADD:
1. **Fibre-guided capillary wick (exact C)** — each pixel pulls colour and coverage from the previous-frame 4-neighbours, weighted per axis by the two fibre octaves (vertical fibres feed the U/D taps, horizontal the L/R taps), and only toward *darker* neighbours so dots grow a feathered, fibre-streaked halo and never erode. Strength rides the existing ink-density role (more ink → more wicking, like the existing wet-bleed).
2. **Dye chromatography fringe (wider C ring)** — chroma (colour minus luma) is low-passed over a ±3 px C ring, so dye runs ahead of the pigment: a coloured feather beyond the dark dot edge, strength tied to the same wick. Luma is untouched (the dark pigment keeps its short range).
FORMULA ADMISSION: both domain-native (capillary wicking / chromatography of ink on paper), no §12.2 row used; each consumes a quantity the file already computes (fibre octaves, posterised colour, ink coverage, own C). Deletion test: remove either → still exactly this halftone; keep only either → not a halftone.
FORBID: fluid/curl advection solver, pointer-spawned ink, springs, ripples, IQ palette, ACES, new params, B writes, audio.
A PACKING: display RGBA (ink colour, ink coverage) — unchanged; C read back with the same meaning.
RESCUES planned: JSON `features` drop the false `fluid-sim`/`curl-noise`/`advection`/`mouse-spawn`, description made truthful (visible behaviour changed). `params` untouched.

---

## SHADER: ink-dispersion-guided
IDENTITY: a depth-guided edge-preserving filter feeds an ink halftone — Sobel ink lines, luma-sized dots on a 45° screen that turns to follow contours, dot feathering by guide variance.
KEEP VERBATIM: 4 params and their (shared) HEAD roles; the whole guided-filter chunk (radius/eps from p1/p2, mouse aperture, ripple depth bump, `a`/`b` linear model); Sobel ink line; posterise; `dotRadius=(1-luma)*0.7`; the edge-tangent screen mechanism (45° base, fold mod 90°, `structure` blend) and guide-variance feather; mouse vignette; depthBoost; A = display RGBA (ink colour, ink coverage).
MECHANISM INTERROGATION:
- tactic 1: the screen angle comes from ONE pixel's 3×3 Sobel — an unsmoothed, sign-ambiguous orientation with no confidence (hence the crude `smoothstep(edge)` blend). Next-better approximation of the same operator: the **structure tensor** of the neighbourhood (orientation + coherence).
- tactic 2: real halftone screens use *elliptical* dots on contours (engravers' dash): dots lengthen along an edge instead of staying round.
- tactic 3: (a) the nine luma taps already fetched give four 2×2 forward-difference gradients for free → a tensor with no new loads; (b) `varGuide` (depth-guide local variance) is computed for the filter and used only to feather dots — promoted, it locates depth discontinuities.
- tactic 6: C is not native here (no continuity a halftone of a static frame needs; ink_dispersion_alpha owns the history idea in this batch) — not added; A stays downstream display RGBA.
ADD:
1. **Structure-tensor tangent + elliptical dashes (§12.2A "Structure-tensor orientation")** — J from the four 2×2 luma cells of the existing 3×3 taps → θ and coherence; θ replaces the single-pixel Sobel angle in the existing fold, coherence gates `structure`, and where coherence is high the dot becomes an ellipse stretched along the contour tangent (long axis picked by the fold parity).
2. **Depth-silhouette ink contour** — `sqrt(varGuide)` thresholded into a thin dark ink line along depth discontinuities (the outline an engraver draws round a near object), blended into the existing ink-line colour/coverage path. Dormant on flat depth, like the guided filter itself.
FORMULA ADMISSION: idea 1 is the §12.2A "Structure-tensor orientation" row (A-owned, edge filter family match: it is an edge-orientation consumer) on the 9 taps already fetched; idea 2 is domain-native (no row). Deletion test passes both ways.
FORBID: C history, springs, new ripples, IQ palette, CMY rosette (would replace the single-screen identity), ACES, new params, audio.
A PACKING: display RGBA (ink colour, ink coverage) — unchanged.
RESCUES planned (hygiene, no `Upgraded:` effect): clamp ripple count to 50; clamp output colour to [0,1] (depthBoost overshoot); replace the time-scaled `paper_tex` with a static per-pixel paper tooth (alpha ±2.5%, same amplitude).

---
## Revision note (after implementation)
See NOTES-forkA.md "Revision of BRIEFS": ink_dispersion_alpha Idea 5 was redesigned (first version invisible in ablation); ink-dispersion-guided Idea 3 (structure tensor + dashes) was measured, found ineffective and replaced by a depth-keyed perspective screen pitch. Silhouette contour (Idea 4) and the C wick (Idea 4/alpha) shipped as carded.
