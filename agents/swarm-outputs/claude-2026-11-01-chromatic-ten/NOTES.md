# Chromatic ten — NOTES (2026-11-01)

Cards: `BRIEFS.md` (written before any WGSL edit). Review: `COORDINATOR_REVIEW.md`.
No GPU in this sandbox: every statement below is **structural** (naga-wasm, SwiftShader pipeline creation,
audits). Nothing here claims an effect "looks right"; real-GPU visual QA is external and still required.

Comment labels: HEAD already used `Idea 1..3` comments in `chromatic-crawler` and `chromatic-focus` and `Native Idea
1..3` in `chromatic-folds-bilateral`, so ideas added in this batch there are labelled `2026-11 Idea n` and `n` matches
the card number. In the other files the label is just `Idea n` (card number).

## Pre-existing findings (flagged, partly repaired — owner decision needed on the rest)

1. **Uniform-order regression, `chromatic-folds-2` and `chromatic-manifold-2` (repaired).** Pre-prelude, both pasted a
   `struct Uniforms` with `zoom_params` before `zoom_config`, i.e. their `u.zoom_config.*` was the sliders and
   `u.zoom_params.*` was engine time/mouse. `migrate_to_prelude.py` refuses that layout on purpose
   ("struct-field-order … needs its own reviewed change"); a hand migration swapped the struct only and added a comment
   claiming the reads stay on the same bytes (they did not). Result at HEAD: manifold-2 fold strength = engine time ·2+0.5
   (unbounded), pivot = mouse x, sat = mouse y, depth influence = mouse-down; folds-2 global intensity = time, etc.
   Repair: every read now hits the bytes it hit before the migration; the four saved sliders drive their named roles
   again. Reads that were never sliders stay on their old bytes (mouse x/y/down) except the two that were engine **time**
   and unbounded (`depthInfluence` in folds-2, `noiseAmount` in manifold-2), which became the old slider midpoint,
   the same remedy `chromatic-crawler` already applied in 2026-10-05.
2. **Time as a parameter in `chromatic-folds` (repaired).** `noiseAmount = u.zoom_config.x * 0.003`, `zoom_config.x` = time,
   so displacement noise grew linearly forever → constant 0.0015 (old midpoint). `feedbackStrength` (mouse x) and
   `rippleStrength` (mouse y) are bounded and **left as they were** — flagged: moving the cursor changes feedback and ripple amplitude.
3. **Not touched, flagged:** `chromatic-manifold` persistence = `zoom_config.z` (mouse y · 0.99, so persistence is 0 at the top
   of the frame and 0.99 at the bottom). `chromatic-folds-bilateral`: `zoom_config.x` (time) → spatial sigma (saturates the capped 11×11
   kernel after ~1 s), `.y` (mouse x) → colour sigma, `.z` (mouse y) → hue shift (so the "psychedelic hue shift" is on whenever mouse y > 0).
   `chromatic-folds-bilateral` and `chromatic-crawler-structure` write ACES display colour into A and read C as colour,
   so the history is tone-mapped again every frame (HEAD packing, consistent, left alone).
4. **Description drift.** `chromatic-folds` JSON promised crease lines, nested history bands, cursor pinch and bass breathing; the
   WGSL at HEAD has none of the pinch/bass/nested-bands (the 2026-10-12 union kept a different variant). I implemented
   *creases* natively (idea 1) and rewrote the description + dropped `audio-reactive` to match the file; resurrecting
   pinch/bass/bands is an owner decision. `chromatic-manifold` JSON promised iso-hue contours, a complementary colour-debt ghost and
   bass-pushed warp; ideas 1–2 + a bass term on the warp make that description true (JSON text unchanged).
5. **`chromatic-folds-bilateral`'s bilateral kernel output was dead** (`srcColor` never read). Idea 1 uses its agreement statistic and its base.
6. **`chromatic-manifold` negative → ACES** (§12.7). Idea 1 fixes it.
7. **`chromatic-focus-coupled` A.z** is `vel.x − vel.y`, labelled vorticity but not the curl. Kept (feeds `twist` and A.z; nothing reads C.z).
   Idea 1 computes the true curl separately as `curlHere`.
8. `chromatic-crawler-structure` re-hashed every region every frame (`time*2.0` in the hash): fixed as idea 3.

## Per shader

### chromatic-folds
- **Kept verbatim:** 4 params and roles; foldHue; 4-tap hue gradient; geodesic bend; sat-tightened exponent; ripple loop; C feedback; mouse x/y reads for feedback/ripple amplitude.
- **A packing:** pre-ACES display RGB in A, A.a = foldAlpha (now + `creaseLine·0.2`); C read as colour — unchanged.
- **Ideas in the diff:** `// ── Idea 2: reverse-sheet tap` (step 6, `backUV`, `sheetColor`); `// ── Idea 1: crease facets` (after `foldedColor`, `facet`, `creaseLine`, stress-whitening).
- **Formula rows:** none (tactic 2/3: promote `delta`; paper-crease artefact).
- **Repair:** `noiseAmount` time → constant.

### chromatic-folds-2
- **Kept verbatim:** all three fold functions (Klein seam, Möbius fibre twist), 5-centre loop, quaternionRotate, chromaticAberration, clock rings, click front, foldAlpha, depth write.
- **A packing:** pre-ACES display RGB + foldAlpha (now + seam) — unchanged.
- **Ideas in the diff:** `Idea 1: fold-basin seams` (loop trackers `strongFold`/`secondFold`, `basinSeam`, seam ridge `outColor * (1 + basinSeam·0.6)`, aberration + alpha terms); `Idea 2: Möbius-dragged history` (`mobiusBest/mobiusCenter` tracking, `dragAngle` rotation of the exact C coordinate).
- **Formula rows:** §12.2E fold-count-as-material (adapted).
- **Repair:** slider reads (finding 1); `depthInfluence` constant 0.5; mouse reads kept (`foldSharpness` mouse x, `rotationSpeed` mouse y·2, `dimensionalFold` mouse-down).

### chromatic-folds-bilateral
- **Kept verbatim:** 4 params; bilateral loop; split foldR/G/B; resonance (HEAD form); ripple sharpening; mouse-radius sigma; hue-shift tail; A = ACES display RGBA.
- **A packing:** ACES display RGBA — unchanged.
- **Ideas in the diff:** `2026-11 Idea 1` (`agreement`/`flatness` after the loop, `displacedColor = mix(rawDisplaced, srcColor, flatness·0.6)`); `2026-11 Idea 2` (`resonanceGate`); `2026-11 Idea 3` (`splitDelta` × pointer distance).
- **Formula rows:** none (tactic 3/4).
- **Floor:** prelude migration (infrastructure; `Upgraded:` bumped because ideas were added, not for the migration).

### chromatic-manifold
- **Kept verbatim:** kNN 4-D search, regression, warp, tears, signed debt in history, mouse-y persistence, Beer-Lambert alpha, A = raw signed colour.
- **A packing:** raw pre-ACES **signed** colour in A (negative debt is the history), A.a = wavelength alpha; ACES on `writeTexture` only, now on `credit + ghost` (never on a negative).
- **Ideas in the diff:** `Idea 2: iso-hue contour lines` (`contourLine`, applied to `outColor` before the persistence mix); `Idea 1: complementary debt ghost` (`debt`/`credit`/`debtGhost`/`displayColor`). Bass × warp strength added so the existing `audio-reactive` claim is true.
- **Formula rows:** none.
- **Heads-up for GPU review:** shadow rendering changed from "ACES of a negative" (accidentally a lifted copy of the shadow) to complement-ghost + mean-debt; coefficients (0.9/0.9) are a guess to keep magnitudes similar.

### chromatic-manifold-2
- **Kept verbatim:** wrapped hue gradient; 5-tap curvature; C.a memory; noise; depth-aware ripples; wavelength alpha; A.rgb pre-ACES + A.a curvature.
- **A packing:** A.rgb pre-ACES display colour, A.a raw curvature memory — unchanged.
- **Ideas in the diff:** `Idea 1: relief-signed pivot split` (`reliefLap`, `pivotHere`); `Idea 2: flow-advected history` (`advPx`, `prevAdv`; fold memory `prev.a` stays in place).
- **Formula rows:** §12.2D semi-Lagrangian advection (this file only).
- **Repair:** slider reads (finding 1); `noiseAmount` constant; feedback/ripple/curve on mouse x/y/down bytes.

### chromatic-crawler
- **Kept verbatim:** crawl field incl. cursor term; Voronoi (+ F2−F1); per-cell epoch re-roll; membranes; upstream C trail; flash/glow/audio; constants for regionSize/glow (HEAD).
- **A packing:** linear pre-ACES RGB (≥0) + coverage alpha; C as colour — unchanged.
- **Ideas in the diff:** `2026-11 Idea 1: cell nuclei` (new `f1` field in `VoronoiCells`, `nucleus`, `nucleusAmt`, alpha); `2026-11 Idea 2: dissolving epochs` (`cellRoll`, used for `regionHash` and `neighHash`; identical to HEAD except the last quarter of each epoch).
- **Formula rows:** none.

### chromatic-crawler-structure
- **Kept verbatim:** tensor + eigenvectors; flow-guided crawl; Cauchy tendrils; 6 swap patterns; birefringence; pulse waves; LIC colour tint; flash; ripples; A = ACES display RGB + coherency alpha.
- **A packing:** display RGBA — unchanged (A.a + spore coverage).
- **Ideas in the diff:** `2026-11 Idea 1` (`licSample`, `licStep ∝ coherency`, per channel); `2026-11 Idea 2: Harris nucleation spores` (`harris`, `spore`); `2026-11 Idea 3: staggered swap epochs` (`regionPhase`, `swapEpoch`).
- **Formula rows:** §12.2A structure-tensor orientation (edge-directed taps; Harris corner measure is the same tensor) — this file only.
- **Floor:** prelude migration; header banner (Category/Complexity/Upgraded added); `upgraded-rgba` feature tag (ACES in WGSL + cards implemented).

### chromatic-focus
- **Kept verbatim:** masks; 6+6 aperture taps; highlight weight; cat's-eye; bokeh fringing; dispersion; halo/iridescence/Mie; split-tone; ACES + dither; A = mask.
- **A packing:** raw mask (focusMask, blurMask, spread·40, alpha), no reader — unchanged.
- **Ideas in the diff:** `2026-11 Idea 1: depth-driven circle of confusion` (`cocScale`); `2026-11 Idea 2: spherical-aberration rim bias` (`rimGain`/`coreGain`). Depth samples moved above the tap loop (same values, same fringe code).
- **Formula rows:** none.

### chromatic-focus-guided
- **Kept verbatim:** spring cursor (untouched), 7 bands/weights, guided filter, sharp mix, ripple shocks, 0.08 persistence.
- **A packing:** ACES display RGBA — unchanged.
- **Ideas in the diff:** `Idea 1: depth-edge-gated dispersion` (`probeDepth`, `crossKeep`, `gatedStrength` in all 7 bands); `Idea 2: focus-plane detail re-injection` (`focusDetail`).
- **Formula rows:** §12.2A guided-filter base/detail — this file only.
- **Floor:** prelude migration; header gets `Upgraded:`/`Ideas:`/`A packing:`.

### chromatic-focus-coupled
- **Kept verbatim:** spring cursor; advection + viscosity; stir/vortex/ripple injection; edge damp/clamp; **raw A = (vel.x, vel.y, vel.x−vel.y, dens)**; C read as fields; focus calc incl. twist from the pseudo-vorticity; ACES only on writeTexture.
- **A packing:** raw sim state — unchanged; not promoted to display history.
- **Ideas in the diff:** `Idea 1: vorticity confinement` (`curlAt`, `confineEps`, `vel +=`); `Idea 2: meniscus lens` (`denGrad`, `meniscusRefract`, `meniscusRim`).
- **Formula rows:** §12.2D vorticity confinement — this file only.
- **Heads-up for GPU review:** confinement strength (`2·(1−viscosity)·clamp(dens)`) is derived, not tuned; check the sim stays stable at viscosity 0 and 1 and with sustained stirring.

## Batch gates

- naga-wasm (30.0): 10/10 valid. SwiftShader WebGPU (`createComputePipelineAsync`, layout auto): 10/10 pipelines created, 0 errors (pipeline creation only — nothing rendered).
- `wgsl_precommit_gate.py --skip-naga --files …`: 10/10 (0 pasted headers, 0 extraBuffer violations). Only the four prelude migrations touched `extraBuffer` lines (none).
- `audit:extrabuffer`: 0 new violations. `audit:dead-sliders -- --files …`: 0 new dead sliders.
- `generate_shader_lists.js`: re-run (descriptions/features for 9 JSONs flow into `public/shader-lists/{artistic,advanced-hybrid}.json`).
- Vitest (`npm run test:ci`): 1608 passed / 1 failed — `shaderDefinitionSchema … gen-abyssal-geode-matrix` in `generative.json`, a file this batch did not touch (pre-existing; see PR).
- `npm run build`: passed.
- Saved `params` byte-identical to HEAD in all 10 JSONs (checked by diffing parsed `params`).
