# Coordinator review — small eight (2026-11-21)

Reviewed against `BRIEFS.md`. Naga and the precommit gate were green on all eight after the idea edits. Real-GPU visual QA is external.

Formulae: fold-count ply (§12.2E) and SDF curvature (§12.2E) are both on `gen-sentient-plasma-silk-nebula-forge` only. No other §12.2 row is new. No formula is shared with a second file.

| Shader | Card | Ideas in the diff | Keep verbatim | Packing | Verdict |
|---|---|---|---|---|---|
| speed-lines-focus | yes | radial ink dashes; stroke taper | zoom blur, spring, FFT voices, click bursts, four sliders | ACES display RGBA | pass |
| gen-sentient-plasma-silk-nebula-forge | yes | fold-count ply (§12.2E); SDF curvature sheen (§12.2E) | fold loop, braid, ion shell, palette, four sliders | ACES display RGBA | pass |
| luma-topography | yes | elevation contours; valley shade | luma normal, sprung light, click fills, four sliders | ACES display RGBA | pass |
| dimension-slicer-guided | yes | depth-snapped rift edge; aberration along the rift normal | slab, guided sums, dual slider roles | ACES display RGBA, A newly written as that color | pass |
| phase-shift | yes | radial zoom-cycle lead; flow group delay | five-layer zoom, per-channel angles, fog, four sliders | ACES display RGBA | pass |
| pixel-tornado | yes | hook echo; updraft shear | tangential blur, debris wall, calm eye, four sliders | ACES display RGBA | pass |
| gen-zeta-function-landscape | yes | analytic slope light; omitted-term grain | eta quotient, rails, walls, ticks, 0.08 C mix | ACES display RGBA | pass |
| quantum-ghost | yes | packet chirp; which-path erasure | packets, visibility, click collapse, raw ghost in A | raw ghost in A, ACES on display | pass |

- [x] Idea Card exists and was written before the diff
- [x] Each numbered idea is pointable in the WGSL (`// ── Idea`)
- [x] KEEP VERBATIM still holds
- [x] Diff is not mostly header / ACES / spring boilerplate
- [x] No generic overlay shared with the previous file
- [x] A packing matches how C is read
- [x] Saved params unchanged. Zeta gained a top-level `params` array copied from its existing `x-meta` so those sliders load
- [x] Springs and ripples only where the file already had them. Luma's spring write is now thread (0,0); the integrator is the same
- [x] Naga 8/8, extraBuffer 0, dead sliders 0. `verify:shaders:fix` 11/11. Vitest 2005 passed, 1 skipped. `npm run build` succeeded. Real-GPU visual QA is external.
- [x] No §12.2 row on more than one file
- [x] Each formula consumes a quantity the file already had
