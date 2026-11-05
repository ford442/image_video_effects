# Sonnet batch 19 — polyhedra, tiling and topology ten — NOTES (2026-11-01)

Cards: `BRIEFS.md` (written before any WGSL edit). Review: `COORDINATOR_REVIEW.md`.

**No GPU in this sandbox.** Checks are structural plus numeric experiments on SwiftShader. Nothing here claims an effect "looks right";
real-GPU visual QA is external and still required.

Comment labels: `2026-11 Idea n` / `Idea n (2026-11)` where HEAD already used numbered ideas; plain `Idea n` elsewhere.

## Did every file's ideas actually change the picture? (HEAD vs new, identical inputs)

Because two earlier-upgraded files in this batch turned out to render nothing (or to hide the effect they are named for), I ran HEAD and the new
version of all ten on the same synthetic inputs (64 px, 6 frames, same mouse/audio/ripples) and measured the display difference. Values include the
repairs, not just the ideas.

| file | mean abs diff | pixels with diff > 0.02 |
|---|---|---|
| gen-rainbow-icosahedron-cascade | 0.493 | 100 % (HEAD was black) |
| gen-islamic-star-rose | 0.232 | 100 % |
| gen-chromatic-zonohedron | 0.155 | 79 % |
| gen-hopf-fibration-fiber-bundle | 0.048 | 46 % |
| gen-quasicrystal-iridescence | 0.042 | 100 % |
| gen-fourier-epicycles | 0.035 | 69 % |
| gen-aperiodic-monotile | 0.012 | 21 % |
| gen-neon-stellated-octahedron | 0.011 | 12 % |
| gen-hyper-dimensional-tesseract-labyrinth | 0.010 | 19 % |
| gen-quasicrystal | 0.003 | 7 % |

The smallest changes (quasicrystal, tesseract struts, neon tubes) are deliberately quiet additions on already-busy pictures.

## Deviations from the cards

1. **gen-quasicrystal-iridescence got a repair that was not on the card.** Its first harness run was *identical to HEAD to four digits*. HEAD's film mix weight is `fresnel · 0.7` with `fresnel = (1 − cosθ)³` and `cosθ = sqrt(1 − dist²/2)`, which never drops below 0.87, so the weight is ≤ 0.0017 everywhere (computed: 0.0000 at the centre, 0.0002 at dist 0.5, 0.0017 at the corner). The soap-film colour the shader is named for was invisible, and so were my two ideas. Repair: grazing angle reaches the frame edge (`cos = sqrt(1 − 2 dist²)`), film weight = 25 % base rising to 85 % at the edge. After the repair the output differs from HEAD (display mean 0.526 → 0.487).
2. **Thresholds were measured, not guessed, and my first guesses were wrong.** gen-quasicrystal: the three-layer sum `qc` has percentiles 2/50/90/98/99.9 = −0.32/0/0.21/0.33/0.49, so my first node thresholds (0.5–0.8) would never have fired; now 0.30–0.45 (top ~2 %). Strain Jacobian percentiles 2/50/90/98 = 0.6/1.7/2.7/3.1; thresholds 2.4–3.1. gen-fourier-epicycles: pen |v| percentiles 0/10/50/90/100 = 0.08/0.34/0.72/1.87/2.29 over 400 frames, while HEAD's `penSpeed` sat at 2.6–3.0 (its cusp term was 0.002 always); `CUSP_K` = 12.
3. **gen-islamic-star-rose packing fix verified numerically:** display range at 30 frames goes from 0.63–0.80 (mean 0.69) to 0.09–0.86 (mean 0.44).
4. **gen-rainbow-icosahedron-cascade repair verified:** HEAD display max 0.084 / alpha max 0.002 → 0.97 / 0.96 (alpha mean 0.33). The corrected edge table was checked against the real icosahedron: 30 distinct edges equal to the 30 vertex pairs at distance 2; all 20 faces built from real edges and distinct.
5. In gen-rainbow-icosahedron-cascade the mouse orbit direction may be mirrored relative to HEAD (the object is rotated instead of the sample plane); only the sense of the orbit, not the structure.

## Pre-existing findings (flagged, not changed)

- gen-fourier-epicycles stores the trail's red/green in A and **synthesises blue as their mean** on read-back (HEAD packing); A also holds unbounded HDR trail (max ~138 measured). Kept.
- gen-hopf-fibration-fiber-bundle: 40 fibres × 32 segments per pixel (HEAD); only per-sample multipliers added.
- gen-aperiodic-monotile history is display colour mixed at 6 % into linear colour (a mild iterated-ACES; not changed, unlike islamic where it dominated).
- gen-islamic-star-rose JSON has no top-level `params` (sliders only in `x-meta.upgrade.params`).
- Remaining prelude-tracker stale entries: 17 on clean `main`, none of this batch's ids.

## Per shader

### gen-quasicrystal
- **Kept verbatim:** 4 params; quasicrystal/quasicrystal2; phason field; Ammann bars; gem colours; A = (trail rgb, bass envelope), B = pre-trail colour + bloom.
- **Ideas:** `2026-11 Idea 1` lattice nodes (`latticeNode`, `NODE_LO/HI`); `2026-11 Idea 2` strain energy glow (`strainJac`, `STRAIN_LO/HI`).
- **Floor:** prelude migration.

### gen-quasicrystal-iridescence
- **Kept verbatim:** 4 params with the HEAD dual mapping; quasicrystal; thin-film integral; Ammann; metals; A = ACES display RGBA.
- **Ideas:** `2026-11 Idea 1` gravity drainage (`mix(0.72, 1.28, uv.y)`); `2026-11 Idea 2` black-film fade (`smoothstep(40, 140, thickness)` in `thinFilmColor`).
- **Repair:** film weight (deviation 1). **Floor:** prelude migration.

### gen-neon-stellated-octahedron
- **Kept verbatim:** all HEAD ideas; A = ACES display RGBA.
- **Ideas:** `Idea 1 (2026-11)` face-identity rim (`tetraFaceIdx`, `faceId`, `faceHue`); `Idea 2 (2026-11)` neon tube profile (`tubeHalo`, `tubeCore`; §12.2F soft inverse-square).
- **Floor:** prelude migration.

### gen-rainbow-icosahedron-cascade
- **Kept verbatim:** vertices, face table, shell scale/gap/pulse, golden-angle yaw, dual sparks, silhouette term, spectral palette, core glow, linear HDR history in A.
- **Ideas:** `Idea 1 (2026-11)` five-fold vertex beads (`beadGlow`); `Idea 2 (2026-11)` signed depth cue (`depthCue`, `cueGain`).
- **Repair (floor):** orthographic wire projection (`pv`, `pz`, 2-D segment distance, projected dual centroids); corrected edge table; dead `icosaShellSDF` / `sdSegment3` removed. **Floor:** prelude migration.

### gen-chromatic-zonohedron
- **Kept verbatim:** 4 params; four generators; zonoSDF/zone/inset/diagonal/star; hue lock; axis shade; A = ACES display RGBA.
- **Ideas:** `2026-11 Idea 1` zonogon silhouette (`zonogonSDF`, support function, outside dimmed to 40 %); `2026-11 Idea 2` tumbling generators (`zonoAxis` now tilts; `zonoSDF` uses `zonoAxis` so every layer agrees).

### gen-hopf-fibration-fiber-bundle
- **Kept verbatim:** all of HEAD (seven ideas).
- **Ideas:** `2026-11 Idea 1` perspective tube thickness (`tubeThick`); `2026-11 Idea 2` aerial cooling (`segColor`). No new loops.

### gen-hyper-dimensional-tesseract-labyrinth
- **Kept verbatim:** all of HEAD; params as saved.
- **Ideas:** `2026-11 Idea 1` hyper-edge struts (`sdCapsule3`, `dStrut`, material 4); `2026-11 Idea 2` w-coordinate colour (w packed with parity: `v = parity·10 + clamp(w, −4, 4) + 4`, decoded in `main`).

### gen-fourier-epicycles
- **Kept verbatim:** 4 params; chain; rim/arm/tick/hub glow; pen glow; trail packing and read-back; gravity well; sparkle.
- **Ideas:** `2026-11 Idea 1` true pen velocity (`penVel`, `penVelMag`, `inkW`, `cusp`; §12.2C speed-thinning); `2026-11 Idea 2` rim comets (`cometTail`).

### gen-aperiodic-monotile
- **Kept verbatim:** all of HEAD.
- **Ideas:** `2026-11` kite seams and second-generation supertile outline (`hatExtras`; `hatTileField`'s vec4 contract unchanged).

### gen-islamic-star-rose
- **Kept verbatim:** sliders; hex tiling; star/n-gon selection; pentagram φ ratio; strapwork rings; nested star; rosette and rose; shadows; chromatic bias.
- **Ideas:** `2026-11 Idea 1` true {n/2} ratio (`trueRatio`; visible change: stars with more than five points are fatter, like real {n/2} stars); `2026-11 Idea 2` interlace (`signedShape`, `strapHidden`).
- **A packing: changed on purpose** — linear temporal mix in A (see deviation 3).

## Formula rows (batch)

| row / mechanism | files |
|---|---|
| F soft inverse-square | gen-neon-stellated-octahedron |
| F thin-film (existing mechanism) | gen-quasicrystal-iridescence |
| C speed-thinning | gen-fourier-epicycles |
| Minkowski support function | gen-chromatic-zonohedron |
| star polygon {n/k} geometry | gen-islamic-star-rose |
| hierarchical inflation | gen-aperiodic-monotile |
| none (tactic-derived) | gen-quasicrystal, gen-rainbow-icosahedron-cascade, gen-hopf-fibration-fiber-bundle, gen-hyper-dimensional-tesseract-labyrinth |

## Gates

- naga-wasm (30.0): 10/10 valid; Tint (Chrome's compiler) via SwiftShader `createComputePipelineAsync`: 10/10.
- `wgsl_precommit_gate.py --skip-naga --files …`: 10/10, 0 pasted headers, 0 extraBuffer violations. `audit:extrabuffer`: 0 new. `audit:dead-sliders -- --files …`: 0 new (9 definitions scanned: gen-islamic-star-rose has no `params`).
- **SwiftShader execution harness** (throwaway, not committed): all 13 bindings, A→C ping-pong, moving mouse, held press, click ripples, synthetic image/depth, non-zero FFT bins; 20–30 frames at 64–96 px (400 frames at 32 px for the epicycles |v| measurement). 10/10 ran: **0 NaN/Inf in display or A, no GPU validation errors.** Plus the HEAD-vs-new difference table above. Numeric sanity only.
- Saved `params` and `x-meta` byte-identical to HEAD in all ten JSONs.
- `generate_shader_lists.js`, `npm run test:ci`, `npm run build`: see PR.
