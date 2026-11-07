# Sonnet batch 19 — polyhedra, tiling and topology ten — COORDINATOR REVIEW (2026-11-01)

This is the author's own pass against the cards, written after the diff. It is a structural review plus numeric checks on SwiftShader.
**There is no GPU here: nothing below says any effect "looks right".** The "look at first on a GPU" list is what a real-GPU reviewer should open first.

Cards: `BRIEFS.md` (written before any WGSL edit). Details and measurements: `NOTES.md`.

## Verdict per file against the §9 / §12.7 checklist

PASS = box holds as far as a structural review can tell. FLAG = holds, but a coordinator should look.

| file | card before diff | ideas pointable | KEEP VERBATIM | < 70 % boilerplate | no shared overlay | A packing truthful | params exact | springs / ripples native | gates |
|---|---|---|---|---|---|---|---|---|---|
| gen-quasicrystal | PASS | PASS (`2026-11 Idea 1/2`) | PASS | PASS | PASS | PASS (unchanged) | PASS | PASS (none added) | PASS |
| gen-quasicrystal-iridescence | PASS | PASS | PASS | PASS | PASS | PASS (unchanged) | PASS | PASS (none added) | PASS — **FLAG: repair not on the card** |
| gen-neon-stellated-octahedron | PASS | PASS | PASS | PASS | PASS | PASS (unchanged) | PASS | PASS (HEAD's `rippleGlow` only multiplies the new rim) | PASS |
| gen-rainbow-icosahedron-cascade | PASS | PASS | **FLAG** (look was black at HEAD; see below) | **FLAG** (diff dominated by the repair) | PASS | PASS (unchanged) | PASS | PASS (none added) | PASS |
| gen-chromatic-zonohedron | PASS | PASS | PASS | PASS | PASS | PASS (unchanged) | PASS | PASS (none added) | PASS |
| gen-hopf-fibration-fiber-bundle | PASS | PASS | PASS | PASS | PASS | PASS (unchanged) | PASS | PASS (none added) | PASS — **FLAG: smallest, third pass** |
| gen-hyper-dimensional-tesseract-labyrinth | PASS | PASS | PASS | PASS | PASS | PASS (unchanged) | PASS | PASS (none added) | PASS |
| gen-fourier-epicycles | PASS | PASS | PASS | PASS | PASS | PASS (unchanged; blue still synthesised) | PASS | PASS (none added) | PASS |
| gen-aperiodic-monotile | PASS | PASS | PASS | PASS | PASS | PASS (unchanged) | PASS | PASS (none added) | PASS |
| gen-islamic-star-rose | PASS | PASS | PASS | PASS | PASS | **A packing changed on purpose, on the card** | PASS | PASS (none added) | PASS |

Boilerplate measure (added lines in the diff, from `git diff -U0`): header/banner/include lines are 2–3 per file against 11–59 added lines. No file gained a spring, ripple, palette or scanline overlay. No new `fwidth`/`dpdx`/`dpdy`.
Prelude migration (four files) *removes* the pasted header; it is the floor and not claimed as an upgrade.

Honest reading of the two FLAG rows in "KEEP VERBATIM / boilerplate":

- **gen-rainbow-icosahedron-cascade.** HEAD sampled its SDF on the plane z = 2.8, outside every shell, so it drew nothing (display max 0.084, alpha max 0.002 measured). I rebuilt the *projection and edge table* so the effect described by its own JSON exists, then added the two ideas. 59 added / 56 removed lines are mostly that repair; the two ideas are about 25 of them. The "keep the look" rule cannot apply to a look that was black, but the coordinator should decide whether the repair belongs in this PR or a separate hygiene PR. Everything HEAD *did* define (vertices, face table, shell scale/gap/pulse, golden-angle yaw, dual sparks, spectral palette, linear HDR history) is kept.
- **gen-quasicrystal-iridescence.** The thin film the file is named for was invisible (film weight ≤ 0.0017 at HEAD), and so would have been my two ideas. The repair changes only the Fresnel angle range and the mix floor. It was found after the card was written, so it is **not on the card** (recorded in `NOTES.md`, deviation 1).

## Per-file pointers (what to open in the diff)

| file | idea 1 | idea 2 | other |
|---|---|---|---|
| gen-quasicrystal | lattice-node pinpoints: `latticeNode`, `NODE_LO/HI` (comment `2026-11 Idea 1`, ~L243) | strain-Jacobian glow: `strainJac`, `STRAIN_LO/HI` (`2026-11 Idea 2`, ~L202 and ~L247) | prelude migrated |
| gen-quasicrystal-iridescence | gravity drainage `mix(0.72, 1.28, uv.y)` (~L120) | black-film fade `smoothstep(40, 140, thickness)` in `thinFilmColor` (~L63) | film-weight repair (~L137) |
| gen-neon-stellated-octahedron | face-identity rim: `tetraFaceIdx`, `faceHue` (~L106, ~L230) | tube profile `tubeHalo`, `tubeCore` (~L199) | prelude migrated |
| gen-rainbow-icosahedron-cascade | five-fold vertex beads `beadGlow` (~L183) | signed depth cue `depthCue`, `cueGain` (~L166) | orthographic wire projection; corrected 30-edge table; dead SDF helpers deleted; prelude migrated |
| gen-chromatic-zonohedron | zonogon silhouette `zonogonSDF` (~L48, ~L230) | tumbling generators in `zonoAxis`; `zonoSDF` uses it (~L41) | — |
| gen-hopf-fibration-fiber-bundle | perspective tube thickness `tubeThick` (~L153) | aerial cooling in `segColor` (~L163) | no new loops |
| gen-hyper-dimensional-tesseract-labyrinth | hyper-edge struts `sdCapsule3`, `dStrut`, material 4 (~L108, ~L252) | w-coordinate colour, w packed with parity in `map`'s 4th output (~L118, ~L226) | — |
| gen-fourier-epicycles | true pen velocity `penVel`, `inkW`, `cusp`, `CUSP_K` (~L126, ~L151) | rim comets `cometTail` (~L109) | — |
| gen-aperiodic-monotile | kite seams (`hatExtras`, ~L124, call ~L210) | second-generation supertile outline (same function) | `hatTileField` vec4 contract unchanged |
| gen-islamic-star-rose | true {n/2} ratio `trueRatio` (~L209) | interlace `signedShape`, `strapHidden` (~L198, ~L235) | linear A packing (end of `main`) |

## Formula names per file (§12.2 / §12.7)

| file | §12.2 row / mechanism | quantity it consumes (already in the file) |
|---|---|---|
| gen-neon-stellated-octahedron | F soft inverse-square (tube halo) | the existing edge distance |
| gen-quasicrystal-iridescence | F thin-film (the file's own mechanism: drainage, black-film fade) | existing film thickness and uv |
| gen-fourier-epicycles | C speed-thinning `w0 / (1 + k|v|)` | the phases and radii the ring loop already holds |
| gen-chromatic-zonohedron | Minkowski support function (zonogon outline) | the four existing generator vectors |
| gen-islamic-star-rose | star polygon {n/k} geometry | the existing n and star/edge distances |
| gen-aperiodic-monotile | hierarchical inflation (a second supertile level) | the existing cell coordinates |
| gen-quasicrystal, gen-rainbow-icosahedron-cascade, gen-hopf-fibration-fiber-bundle, gen-hyper-dimensional-tesseract-labyrinth | none (tactic-derived) | plane-wave sum / strain noise; vertices and edges; per-segment depth; the 4-D coordinate |

No row appears on more than one file; the batch theme (geometric vocabulary) is not itself a formula. No pair of files shares both ideas.

## §12.7 additions

- [x] `BRIEFS.md` contains the mechanism interrogation per card (and the findings section that shaped them).
- [x] Every formula is named in `NOTES.md` and in each file's `Ideas (2026-11):` banner line.
- [x] No §12.2 row on more than two files (maximum is one).
- [x] Each formula consumes a quantity the file already had. No new binding, solver, spring or state; the one extra piece of state is w riding in the *existing* fourth output of the tesseract `map`.
- [x] No `fwidth`/`dpdx`, no `pow` with an unguarded base (the one added `pow(1 − cosThetaWide, 3)` has base in [0, 0.86]: `cosThetaWide = sqrt(max(…, 0.02)) ≤ 1`), no negative input to ACES (A packing in islamic stores the linear mix, which is ≥ 0, and ACES is applied only to the display write).

## Look at first on a real GPU

1. **gen-rainbow-icosahedron-cascade** — the whole picture. HEAD was black, so the first real look is the first look. Check that the wireframe shells read as an icosahedron, that bass expansion and the click pulse still move the shells, and which way the mouse orbit turns (the object is now rotated instead of the sample plane; the sense may be mirrored relative to what the author intended).
2. **gen-quasicrystal-iridescence** — the film is now a visible base layer (25 % mix rising to 85 % at the frame edge). Judge whether that is too strong or too weak; the constants are `0.25` and `0.85` in the Fresnel mix, `smoothstep(40, 140, …)` for the black film.
3. **gen-islamic-star-rose** — contrast and brightness (display range measured 0.09–0.86 instead of 0.63–0.80); 6/7/8-point stars are fatter than at HEAD; check the interlace gaps hide strap rings inside the shapes without leaving stubs.
4. **gen-chromatic-zonohedron** — zonogon outline and the 40 % dim outside it; whether the tilt of the generators looks like a turn or a wobble.
5. **gen-fourier-epicycles** — the comet sits behind each arm tip in the sense of rotation (every wheel turns toward increasing phase because `freq = fi · speed · (1 + mids · 0.15)` and `speed > 0`; the mouse-x phase term shifts all wheels while the pointer moves, so the tail may briefly look ahead of the motion then); cusp blots appear at the cusps and not along straight runs; trail blue is still synthesised from red/green (HEAD).
6. **gen-hyper-dimensional-tesseract-labyrinth** — hyper-edge struts (material 4) and the warm/cool w colour. One capsule is evaluated per sample, from the corner of the sample's octant to the matching ghost-frame corner; look for a seam or pop where the octant (and so the chosen corner) switches at the cell's midplanes, and for struts that stop short of the ghost frame's corners (ghost centre is `-wShift`, half-size 0.85).
7. **gen-hopf-fibration-fiber-bundle** — runtime cost (40 fibres × 32 segments per pixel at HEAD; nothing added to the loop) and whether tube thinning / cooling is visible at all.
8. **gen-quasicrystal**, **gen-neon-stellated-octahedron**, **gen-aperiodic-monotile** — deliberately quiet additions (measured mean difference to HEAD 0.003, 0.011, 0.012); judge whether the nodes, face hues, tube cores and seams are visible enough at default sliders.

## Calibrated constants a reviewer can retune

Measured on SwiftShader, not on a GPU: quasicrystal `NODE_LO/HI` = 0.30/0.45 (top ≈ 2 % of the sum) and `STRAIN_LO/HI` = 2.4/3.1; epicycles `CUSP_K` = 12 (pen |v| percentiles 0/10/50/90/100 = 0.08/0.34/0.72/1.87/2.29); iridescence film weight 0.25 → 0.85 and black-film range 40 → 140 nm; zonohedron outside dim 0.4.

## Not done / left for a decision

- gen-hopf-fibration-fiber-bundle cost (HEAD's 40 × 32 loop) is unchanged and unmeasured on a GPU.
- gen-fourier-epicycles still synthesises trail blue from red/green and keeps unbounded HDR in A (HEAD packing; max ≈ 138 measured). Changing it is a packing decision, not an idea.
- gen-aperiodic-monotile still mixes display colour at 6 % into linear history (mild iterated ACES). Left as is.
- gen-islamic-star-rose has no top-level `params` in its JSON (sliders only in `x-meta.upgrade.params`).
- Restored shaders: **none**. No file needed the three-attempt restore.

## Gates (details in `NOTES.md` and the PR)

naga-wasm 10/10; Tint via SwiftShader pipeline creation 10/10; `wgsl_precommit_gate.py` 10/10; `audit:extrabuffer` 0 new; `audit:dead-sliders` 0 new; SwiftShader execution harness 10/10 with 0 NaN/Inf; saved params and `x-meta` byte-identical in all ten JSONs; shader lists regenerated (only these ten descriptions changed); `npm run test:ci` 1609 passed, 1 skipped, 0 failed and `npm run build` passed, both re-run on the tree merged with current `main`; `check_prelude_migration.py` passes. **Real-GPU visual QA: external.**
