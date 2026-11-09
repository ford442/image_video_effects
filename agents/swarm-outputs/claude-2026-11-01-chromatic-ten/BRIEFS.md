# Chromatic ten — Idea Cards (written before any WGSL edit)

Batch: `claude-2026-11-01-chromatic-ten` · date 2026-11-01 · model: Claude · explicit id list (no "pick N").
Theme that already lives in the files: the `chromatic-*` family (hue folds, 4-D colour manifolds,
Voronoi/structure-tensor crawlers, chromatic focus/bokeh).

Claimed ids (no overlap with another agent): chromatic-folds, chromatic-folds-2, chromatic-folds-bilateral,
chromatic-manifold, chromatic-manifold-2, chromatic-crawler, chromatic-crawler-structure,
chromatic-focus, chromatic-focus-guided, chromatic-focus-coupled.

Ledger history read before carding (reports/shader-upgrade-ledger.json):

| id | prior ledger events | Notes |
|---|---|---|
| chromatic-folds | upgraded 2026-10-05, 2026-10-12 | second pass; HEAD `Ideas:` = geodesic bend; saturation-tightened foldHue |
| chromatic-folds-2 | upgraded 2026-10-12 | second pass; HEAD `Ideas:` = Klein orientation seam; Möbius fiber twist |
| chromatic-folds-bilateral | none | never upgraded (has 2026-09-06 header, no ledger event); pastes binding header |
| chromatic-manifold | upgraded 2026-10-05, 2026-10-12 | second pass; HEAD `Ideas:` = hue-distance neighbour weights; Beer-Lambert thickness |
| chromatic-manifold-2 | upgraded 2026-10-12 | second pass; HEAD `Ideas:` = laplacian smooth of curvature; C.a fold memory |
| chromatic-crawler | upgraded 2026-10-05 | second pass; HEAD `Ideas:` = membranes; streaming trails; cursor joins crawl |
| chromatic-crawler-structure | none | never upgraded; pastes binding header; no `Upgraded:` header |
| chromatic-focus | upgraded 2026-10-05 | second pass; HEAD `Ideas:` = highlight bokeh discs; cat's-eye; bokeh fringing |
| chromatic-focus-guided | none | never upgraded; pastes binding header |
| chromatic-focus-coupled | none | never upgraded; pastes binding header |

Ideas already shipped in HEAD are NOT re-added below. Every card adds different ones.

## Findings that shape the cards (read before the cards)

1. **Uniform-order regression in `chromatic-folds-2` and `chromatic-manifold-2`.** Their pre-prelude pasted
   `struct Uniforms` listed `zoom_params` *before* `zoom_config` (engine layout is config, zoom_config, zoom_params).
   So in the old code `u.zoom_config.*` read the four UI sliders and `u.zoom_params.*` read engine time / mouse.
   `scripts/migrate_to_prelude.py` refuses exactly this layout (REASONS["struct-field-order"]); a hand migration
   swapped the struct to canonical but left every read, and added a comment ("reads stay on the same bytes") that is
   false. Today the saved sliders of both files do not drive what their names say (fold strength = time, pivot = mouse X…).
   Plumbing-floor repair: swap each read to the uniform that holds the same bytes as before the migration. That makes
   the saved sliders live again and nothing else changes. Reads that were *never sliders* (engine time / mouse used as
   a parameter) are kept on their original bytes, except where they grow without bound in time — those become the
   slider midpoint constant, following the precedent already set by `chromatic-crawler` (HEAD comment "HEAD read these
   from zoom_config (time / mouse)… Now the old midpoints").
2. **JSON/WGSL description drift** in `chromatic-folds` and `chromatic-manifold`: the JSON describes crease lines,
   nested bands, cursor pinch, bass breathing (folds) and iso-hue contours, complementary colour-debt ghost, bass-pushed
   warp (manifold) that are not in HEAD's WGSL (the 2026-10-12 union merge kept a different variant). Manifold's cards
   below implement the described contour + debt ghost natively; folds' description is rewritten to match the file.
3. **Negative colour into ACES** in `chromatic-manifold` (shadow "colour debt" is stored negative and tone-mapped
   directly). §12.7 forbids negative ACES input. Idea 1 of that card is the fix *and* the visible idea.
4. `chromatic-folds-bilateral` computes a bilateral-smoothed `srcColor` and never reads it again (the kernel output is
   dead). Idea 1 of that card wires the kernel's own agreement statistic into the fold.

---

## SHADER: chromatic-folds
IDENTITY: the source image whose hues are folded around a pivot hue (pow-fold in HSV), displaced along the hue gradient, with history feedback and click ripples.
KEEP VERBATIM: 4 saved params (fold strength → foldExp, pivot hue, sat scale, depth influence → curvature); foldHue(); hue-gradient finite differences; geodesic bend; saturation-tightened exponent; click ripple loop; feedback mix with exact C `.rgb`; A = pre-ACES display RGB + alpha.
MECHANISM INTERROGATION:
- tactic 2 (physics one step further): a *fold* has a crease. The shader folds hue about a pivot but nothing shows the crease or its two faces.
- tactic 3 (promote an intermediate): `foldHue` computes `delta = h − pivot` and throws it away; its sign is which face of the fold a pixel is on, its magnitude the distance to the crease.
- tactic 6 / 5: a folded sheet shows its back where the fold overlaps; `totalDisp` + `hueGrad` already say where the sheet is being displaced hard.
ADD:
1. Crease facets — the two hue faces of the fold are lit/shaded by sign(h−pivot) and the pivot line itself stress-whitens (paper crease): value ±16 % by face, hairline desaturated-bright at |Δh|≈0. Uses the pre-fold hue delta already implied by foldHue.
2. Reverse-sheet tap — one extra source tap at `uv − totalDisp` (the back face of the displaced sheet), shaded 0.82 and blended in only where `|hueGrad|` is large, so folds overlap at hue edges instead of only stretching.
REPAIR (not an idea): `noiseAmount` read `zoom_config.x` = engine **time** (displacement noise grew linearly forever) → midpoint constant 0.0015. Mouse reads for feedback/ripple amplitude are bounded and left on their bytes.
FORMULA ADMISSION: tactic-derived, no §12.2 row consumed (artistic fold; native noun = crease/sheet).
FORBID: springs, IQ palettes, new params, replacing HSV fold.
A PACKING: unchanged — pre-ACES display RGB in A, `foldAlpha` (now + crease) in A.a; C read as colour.

## SHADER: chromatic-folds-2
IDENTITY: five roaming fold centres cycling Möbius / Klein / hyperbolic colour-space folds over the image, quaternion-ish rotation, fold-edge aberration, clock rings, click front.
KEEP VERBATIM: mobiusFold/kleinFold/hyperbolicFold bodies (incl. Klein orientation seam, Möbius fiber twist), 5-centre loop and fold-type cycle, quaternionRotate, chromaticAberration, clock rings + click front, 4 saved sliders (global intensity, hyper factor, twist rate, chromatic scale), foldAlpha, A = pre-ACES display RGB.
MECHANISM INTERROGATION:
- tactic 3: `localFoldStrength` per centre is computed and only summed. Its max and runner-up say where two fold basins meet — the *join* of the manifold.
- tactic 6: C is read at the same pixel; a Möbius fold is non-orientable — a trail that crosses it should come back twisted, not in place.
ADD:
1. Fold-basin seams — track the strongest and second-strongest `localFoldStrength` per pixel; where they are equal (and both non-trivial) draw a thin ridge: brightness bump + extra fold-edge aberration on that seam (§12.2E fold-count-as-material, adapted: how many folds claim a pixel).
2. Möbius-dragged history — the exact C tap is rotated about the strongest Möbius centre by up to ~0.06 rad × its strength, so the trail twists as it crosses a Möbius fold (exact integer `textureLoad`, no sampler).
REPAIR (floor): slider reads swapped to the uniform holding the same bytes as pre-migration (see finding 1); `depthInfluence` (was engine time, unbounded) → midpoint 0.5; foldSharpness/rotationSpeed/dimensionalFold stay on their original bytes (mouse x / mouse y·2 / mouse-down).
FORMULA ADMISSION: E fold-count (this file only); history twist is tactic 6.
FORBID: new fold type, new palette, extra springs, replacing the click front.
A PACKING: unchanged — pre-ACES display RGB + foldAlpha (seam adds a little coverage).

## SHADER: chromatic-folds-bilateral
IDENTITY: chromatic hue folding on a joint colour/depth bilateral neighbourhood, with split-spectrum pivots and contour resonance waves.
KEEP VERBATIM: 4 saved params; the 11×11 joint colour+depth bilateral loop; multi-spectral split foldR/G/B; contour resonance; ripple sharpening; mouse-radius sigma modulation; hue-shift tail; A = ACES display RGBA (C read as colour, documented).
MECHANISM INTERROGATION:
- tactic 3: the kernel's `accumWeight` vs the spatial-only weight sum is a free *agreement* statistic (1 in flat regions, low at colour/depth edges) and the smoothed `srcColor` it builds is never used (dead).
- tactic 4: `splitDelta` is one constant for the whole frame; real lateral dispersion grows with distance from the optical axis, and this file already owns a pointer distance (`mouseDist`).
ADD:
1. Bilateral base feeds the fold — flat-agreement pixels fold the edge-preserved `srcColor` (blend up to 0.6) instead of the raw displaced tap, so flat areas fold clean and edges keep their raw hue (promotes the dead kernel output).
2. Edge-gated resonance — the contour standing-wave amplitude is scaled by (1 − agreement): nodes sit in flat regions, antinodes ride preserved boundaries.
3. Pointer-radial dispersion — `splitDelta` scales 0.55 + 1.3·mouseDist, so the split-pivot fringes tighten near the cursor and open outward (prism focus).
REPAIR/floor: migrate pasted header to `_prelude.wgsl` (infrastructure). The three hidden `zoom_config` reads (time→spatial sigma, mouse x→colour sigma, mouse y→hue shift) are **left as-is** and flagged: after ~1 s the time read saturates the capped 11×11 kernel, mouse reads are bounded.
FORMULA ADMISSION: tactic 3/4; no table row.
FORBID: springs, IQ palettes, new params, changing the A packing.
A PACKING: ACES display RGBA (HEAD, kept; noted that C therefore holds tone-mapped colour).

## SHADER: chromatic-manifold
IDENTITY: 4-D (uv, depth, hue·chroma) manifold: nearest-neighbour hue gradient warps a persistent history; HDR tears; shadow "colour debt"; wavelength-dependent alpha.
KEEP VERBATIM: 4 saved params (color boost, warp, tear threshold, curvature); 4-nearest 4-D neighbour search + hue regression; warp of history lookup; HDR tear smear; signed debt in shadows stored in history; persistence read from `zoom_config.z`; Beer-Lambert wavelength alpha; A = raw pre-ACES signed colour + alpha (C read as colour).
MECHANISM INTERROGATION:
- tactic 3: `grad` is the manifold's own hue slope in uv; with `hueW` it fully determines the level sets of the hue field (iso-hue lines), which nothing draws.
- tactic 6: debt is *negative* history; the display tone-maps it directly (ACES of negative input → bright artefact).
ADD:
1. Complementary debt ghost — display = credit + ghost, where ghost = (max-debt − debt) + mean-debt (hue-complement of what is owed), instead of tone-mapping negative numbers. Stored A keeps the signed debt (that *is* the history).
2. Iso-hue contour lines — lines where `fract(8·hueW)` crosses 0.5, width normalised by |grad| to ~1.5 px, chroma-weighted, added **before** the persistence mix (no feedback gain); bass pumps the warp (makes the existing `audio-reactive` claim true).
FORMULA ADMISSION: tactic 3 / 6; no table row.
FORBID: replacing the kNN regression; palette swaps; springs.
A PACKING: unchanged — raw pre-ACES signed colour (may be negative) + wavelength alpha; display ACES only on `writeTexture`.

## SHADER: chromatic-manifold-2
IDENTITY: image displaced along the hue gradient, hue-folded around a pivot, with depth-curvature, C.a fold memory, ripples, wavelength alpha.
KEEP VERBATIM: 4 saved sliders (fold strength, pivot hue, sat scale, depth influence); wrapped hue gradient; 5-tap curvature smoothing; C.a fold memory → harder fold; noise displacement; depth-aware ripples; wavelength alpha; A = pre-ACES colour with A.a = raw curvature memory.
MECHANISM INTERROGATION:
- tactic 3: the five depth taps are fetched to *blur* curvature; their mean minus the centre is the true Laplacian whose sign says ridge vs valley.
- tactic 6: C is read in place while the picture is being displaced along `totalDisp`; the history should be carried by the same flow.
ADD:
1. Relief-signed pivot split — pivot is nudged ±0.07 by the sign of the depth Laplacian (valleys fold about one pivot, ridges about another), so folds follow relief.
2. Flow-advected history — the colour history is read at `px + clamp(totalDisp·dims·0.3, ±2 px)` (semi-Lagrangian, exact integer load) so persistence trails stream along the fold flow; fold memory stays in-place (it feeds dispBase before the flow exists).
REPAIR (floor): sliders re-pointed as in finding 1; `noiseAmount` (was engine time, unbounded) → midpoint 0.0015; feedbackPersist / rippleAmp / curvePower stay on their original bytes (mouse x / mouse y / mouse-down).
FORMULA ADMISSION: D semi-Lagrangian advection (this file only).
FORBID: springs, IQ palette, new params.
A PACKING: unchanged — A.rgb pre-ACES display colour, A.a raw curvature memory.

## SHADER: chromatic-crawler
IDENTITY: Voronoi cells that crawl under a displacement field, each re-rolling its hue/spectral tint, membranes, streaming trails, cursor as a 4th crawl centre.
KEEP VERBATIM: 4 saved params; createCrawlingRegions incl. cursor term; voronoiRegions; cell epoch hue re-roll; spectralTint; membranes; upstream C trail; flash; glow; audio; A = linear pre-ACES colour + coverage alpha.
MECHANISM INTERROGATION:
- tactic 5 (artifact of the real thing): cells under a microscope have a nucleus; the seed point and F1 are already computed.
- tactic 2: a hue re-roll is a hard pop on the epoch boundary (`floor`); a living cell changes colour continuously.
ADD:
1. Cell nuclei — a soft nucleus at each Voronoi seed (F1 < ~0.2 cell units) tinted with the cell's own wavelength; fades with the membranes when cells shrink below ~6 px; raises coverage alpha.
2. Dissolving epochs — each cell cross-fades between hash(epoch) and hash(epoch+1) in the last quarter of its epoch instead of popping (applied to cell hue and to the neighbour tint behind the membranes).
FORMULA ADMISSION: tactic 2 / 5; no table row.
FORBID: springs, ripples, IQ palette (cursor already in the crawl).
A PACKING: unchanged — linear pre-ACES RGB (≥0) + coverage alpha; C read as colour.

## SHADER: chromatic-crawler-structure
IDENTITY: colour-swapping crawl guided by the image's structure-tensor eigenvectors, with Cauchy tendril split, photoelastic fringes and bioluminescent pulses.
KEEP VERBATIM: 4 saved params; smoothTensor / eigen decomposition; flow-guided crawl offset + mouse attract; RGB-offset tendrils; 6 swap patterns; birefringence fringes; pulse waves; LIC tint; flash; ripples; A = ACES display RGB + coherency alpha.
MECHANISM INTERROGATION:
- tactic 7 (direction, not magnitude): the eigenvector field exists but the image is only *sampled at* a point per channel; "LIC tint" is only a colour. Taps along ±eigenvec make the flow physical.
- tactic 3: `lambda2` is only used inside coherency; with λ1 it gives the Harris corner measure — where structure nucleates rather than runs.
- the swap hash uses continuous `time*2.0` ⇒ re-rolls every frame (frame-hash strobing; the sibling chromatic-crawler already fixed this with staggered epochs).
ADD:
1. Line-integral crawl — 5-tap Gaussian line integral along ±eigenvec per channel (R/G/B each on its own tendril UV); step length ∝ coherency so incoherent areas stay point-sampled (§12.2A structure-tensor orientation, edge-directed taps).
2. Harris nucleation spores — `λ1λ2 − 0.05(λ1+λ2)²` marks corners; a twinkling spore in the existing birefringence fringe colour blooms there and raises alpha.
3. Staggered swap epochs — each 10×8 region holds its channel permutation for ~0.5 s on its own phase instead of re-hashing every frame.
FORMULA ADMISSION: A structure tensor (this file only; none other in batch).
FORBID: springs, new palette, replacing the tensor.
A PACKING: unchanged — ACES display RGBA (RGB display, A = confidence).
FLOOR: migrate pasted header to prelude; add header banner.

## SHADER: chromatic-focus
IDENTITY: cursor-centred in-focus region with the rest blooming into chromatic bokeh (12-tap rimmed discs, cat's-eye, fringes), OkLab split-tone, halo, ACES.
KEEP VERBATIM: 4 saved params; focus/blur masks; 6+6 tap rotating aperture; highlight weighting; cat's-eye clip; bokeh fringing; dispersion offsets; halo/iridescent/Mie terms; split-tone; ACES + dither; A = mask fields (no reader).
MECHANISM INTERROGATION:
- tactic 3: `pixDepth` and `focusDepth` (hence `defocus`) are sampled *after* the tap loop and only used for the fringe colour; the blur radius ignores depth.
- tactic 2: real lenses have a circle of confusion ∝ |depth − focus plane| and spherical aberration that makes front and back bokeh different.
ADD:
1. Depth-driven circle of confusion — blur radius × (1 + clamp(3|defocus|, 0, 1)); flat depth gives exactly the old radius.
2. Spherical-aberration rim bias — rim weight bias keyed by the sign of `defocus`: behind the focus plane discs go bright-edged (rim heavier), in front they go soft/centre-heavy; zero defocus keeps HEAD's 0.35 rim constant.
FORMULA ADMISSION: tactic 2 (optics); no table row.
FORBID: new spring, new overlay palette, changing the A mask.
A PACKING: unchanged — raw mask (focusMask, blurMask, spread·40, alpha), no reader.

## SHADER: chromatic-focus-guided
IDENTITY: 7-band Cauchy chromatic dispersion pushed away from a spring-damped cursor focus, depth-guided filter for edge-safe blur, click shocks.
KEEP VERBATIM: 4 saved params; spring cursor in extraBuffer[133..138]; 7 spectral bands + weights; 7×7 guided filter mix; sharp mix; ripple shocks; 0.08 C persistence; A = ACES display RGBA.
MECHANISM INTERROGATION:
- tactic 1 (deepen kernel): the stated purpose ("prevent cross-edge dispersion bleeding") is only met by mixing the filter in as colour; the dispersion taps themselves cross depth boundaries freely.
- tactic 3: `guidedResult` (edge-aware base) vs the sharp tap is a base/detail split that is never exploited.
ADD:
1. Depth-edge-gated dispersion — one probe at the dispersed position; if its depth differs from the centre's, effective dispersion strength falls to 0.3× (joint-depth range weight), so fringes stop at silhouettes. Flat depth leaves it at 1×.
2. Focus-plane detail re-injection — (sharp − guided base) clamped to ±0.25 is added back by the in-focus weight, restoring crispness inside the focus disc without crossing depth edges (§12.2A guided-filter base/detail).
FORMULA ADMISSION: A guided-filter base/detail (this file only).
FORBID: touching the spring, new palette, new params.
A PACKING: unchanged — ACES display RGBA; C read as colour.
FLOOR: migrate pasted header to prelude; add header Upgraded/Ideas/A-packing lines.

## SHADER: chromatic-focus-coupled
IDENTITY: chromatic DOF whose focus centre, twist and blur are driven by a viscous fluid the spring cursor stirs; click bursts inject fluid.
KEEP VERBATIM: 4 saved params (aberration, blur, focus radius, viscosity); spring cursor; semi-Lagrangian advection with viscosity; stir + vortex + ripple injection; edge damping/clamp; **raw sim state in A (vel.xy, pseudo-vorticity `vel.x − vel.y`, density)**; C read as fields; chromatic focus calc incl. twist; ACES only on writeTexture.
MECHANISM INTERROGATION:
- tactic 1/3: the grid solver damps small swirls (viscosity); its own velocity field in C.xy has a true curl no one reads (the `vorticity` var is `vx − vy`, kept because it feeds `twist` and A.z).
- tactic 6: density in C.a has an edge (the dye boundary) that the optic never reacts to.
ADD:
1. Vorticity confinement (§12.2D D1) — true curl from C.xy neighbours, N = ∇|ω|/|∇|ω||, force ε·(N.y, −N.x)·ω with ε = 2·(1−viscosity)·clamp(dens) so it only restores the swirl energy viscosity removed, inside dyed fluid.
2. Meniscus lens — ∇density from the same C neighbours: a rim highlight on the lit side of the dye edge and a small refraction of the three channel taps along ∇dens.
FORMULA ADMISSION: D vorticity confinement (this file only).
FORBID: replacing the solver, display-history sparkles, promoting raw A to display, Gray-Scott.
A PACKING: unchanged raw sim — A = (vel.x, vel.y, vel.x − vel.y, dens). Display tone-mapped only on writeTexture.
FLOOR: migrate pasted header to prelude; add header banner.

---

## Formula-row ledger for this batch (≤2 files per row)

| §12.2 row | files |
|---|---|
| E fold-count as material | chromatic-folds-2 |
| D semi-Lagrangian advection (C table) | chromatic-manifold-2 |
| A structure tensor / edge-directed taps | chromatic-crawler-structure |
| A guided-filter base/detail | chromatic-focus-guided |
| D vorticity confinement | chromatic-focus-coupled |
| none (tactic-derived) | folds, folds-bilateral, manifold, crawler, focus |
