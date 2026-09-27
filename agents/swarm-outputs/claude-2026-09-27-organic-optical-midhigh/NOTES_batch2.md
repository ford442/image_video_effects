# Notes — batch 2 of 2 (shaders 6-10)

All 5 files: `naga` clean and `wgsl_precommit_gate.py` clean (bindgroup-compatible). No GPU on this VM — structural proof only, no visual QA claim. Saved `params` (ids/names/defaults/min/max/step) untouched in all 5 JSON files; no JSON edits were needed (existing `features` tags remained truthful after the edit).

## gen-cosmic-velvet-hypnosis
- Kept verbatim: spiral/octave-well math, drag-torque mouse mechanic, palette, params, ripple halos, both existing ideas.
- New ideas in diff: `runner2`/`counterPhase` (counter-runner comet), `runnerCollision` (crossing flash), `seamGlint` (runner × seamLip interaction). All three are pointable at lines added after `seamLip` and folded into the `hdr` accumulation and `structure` (alpha) terms.
- A packing: unchanged — ACES display RGBA in both `writeTexture` and `dataTextureA`.
- Gate: naga OK, precommit gate OK.

## gen-cymatic-plasma-mandalas
- Kept verbatim: kaleidoscope fold, hex+circle SDF blend, spring-mouse vortex (`extraBuffer[133..138]` untouched), click nodal rings, params, temporal symmetry memory, depth edge glow.
- New ideas in diff: `waveBass`/`waveMids`/`waveTreble`/`waveSum` (three-band interference replacing the single sine), `nodeProximity`/`sandSpeckle` (standing-wave sand). Folded into `d` (the SDF) and added to `col`/`alpha`.
- Plumbing fix: added a proper `Ideas:` + `A packing:` header line (previously only a prose hygiene note existed).
- A packing: unchanged — A/C = final ACES display RGBA; exact temporal symmetry memory.
- Gate: naga OK, precommit gate OK.

## gen-depth-refracted-liquid-stained-glass
- Kept verbatim: depth-heightfield refraction, facet fold, three-point lighting, ornamentSample, thinFilmTint, click-wave flex, params.
- New ideas in diff: `seamKey`/`leadHighlight` (leaded-came specular seam), `causticStrength` (depth-driven caustic focus glow from existing `offset` magnitude). Added to `col` before the temporal tint blend, and folded into `materialCoverage`/alpha.
- Plumbing fix: added a proper `Ideas:` + `A packing:` header line (previously only a feature list, no Ideas line).
- A packing: unchanged — A/C = final ACES display RGBA; exact stained-glass tint history.
- Gate: naga OK, precommit gate OK.

## gen-cybernetic-ferro-coral
- Kept verbatim: warpedFbm spike mechanic, turingBand shell carving, mouse-repulsion field, core/shell split, params, ripple spike-boost. Did not touch extraBuffer (file explicitly documents it uses none).
- New ideas in diff: `bandAtHit`/`circuitGlow` (Turing-band circuit trace) and `pulseRaw`/`pulsePhase`/`signalPulse` (outward treble-keyed signal pulse), both added inside the `marchRay` hit branch right after `coreEmission`/`col` are computed.
- Plumbing fix: header previously had a "Batch 36 — Algorithmist / By: Kimi Agent" attribution stamp instead of a proper `Ideas:` line — normalized to the standard 7-line banner. Provenance is preserved in git history and the JSON `description` field, which still credits Batch 36.
- A packing: unchanged — A/C = raw HDR display RGBA history.
- Gate: naga OK, precommit gate OK.

## gen-chrono-voronoi-mycelium
- Kept verbatim: multi-generation Voronoi growth, nutrient/clickSurge mechanics, velocity-advected HDR history/flow field, the pre-ACES-in-A / ACES-on-writeTexture packing (left exactly as-is, not normalized to match the other 9 files), params, both existing ideas (clamp connections, apothecia cups).
- New ideas in diff: `myceliumBranch` return type changed from `vec2<f32>` to `vec3<f32>` to expose `rebirthFlash`; `cyclePeriod`/`cycleRaw`/`cycleT` replace the old one-shot `birthTime` age curve with a wrapped per-cell clock (cyclic regeneration); `rebirthGlow` accumulates `rebirthFlash` per generation and is composited as a green spark, folded into `color`, `alpha`, and `depth`.
- A packing: unchanged and explicitly preserved per the Idea Card's FORBID clause.
- Gate: naga OK, precommit gate OK.
