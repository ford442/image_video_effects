# Notes — organic/optical mid-high ten (2026-09-27)

All 10 files: `naga` clean and `python3 scripts/wgsl_precommit_gate.py` clean. Saved `params` (ids/names/defaults/min/max/step) left byte-exact in all 10 JSONs — only `updatedParams`/`features`/`feedbackPacking` were added or aligned. No GPU on this VM — structural proof only, no visual QA claim. See `NOTES_batch1.md` / `NOTES_batch2.md` for the per-fork originals.

## gen-bioluminescent-neural-lattice
- Kept verbatim: dual-voronoi SDF, camera flythrough, mouse warp, all 4 param roles.
- A packing: display RGBA, afterglow-blended (`max(current, decayed history)`); same value in `writeTexture` and `dataTextureA`.
- Ideas in diff: `voronoi_edges_id()` (new) → `fire_pulse` term in `map()` and `fire_glow` accumulation in `main()` (Idea 1); `textureLoad(dataTextureC, id, 0)` + `afterglow_decay`/`trailed` (Idea 2); `ambient * (1.0 + treble * 0.6)` (Idea 3).
- Plumbing fixed: real `plasmaBuffer[0].xyz` (was self-sampling `dataTextureC` as fake audio); `dataTextureA` now written; `writeDepthTexture` now written (was never called at all).
- Naga: clean.

## gen-biomechanical-hive
- Kept verbatim: hex-prism `map()`, core/wall material split, breathing/pulse mechanic, all 4 param roles, orbit camera.
- A packing: raw HDR display RGBA history (pre-ACES) in A/C, ACES only on `writeTexture` — documented in header and JSON `feedbackPacking`.
- Ideas in diff: `history`/`growthDecay`/`trailedColor` block before ACES (Idea 1); `vein_pattern`/`veins` term added to `d_organic` in `map()` (Idea 2); `nerveSeed`/`nerveFlicker` in the wall shading branch (Idea 3).
- Plumbing fixed: `dataTextureA`/`dataTextureC` wired for the first time (previously both dead).
- Naga: clean.

## gen-celestial-aether-seraphim-wings
- Kept verbatim: KIFS fold loop, flap oscillator, lift/stall model (C_L, stall smoothstep), all 4 param roles.
- A packing: display RGBA, unchanged (same value in `writeTexture`/`dataTextureA`).
- Ideas in diff: `alphaAOA_map`/`stallAmt`/`shedPhase`/`vortex` perturbation inside the fold loop in `map()` (Idea 1); `liftHueShift` term added to the iridescence `hue` calc in `main()` (Idea 2).
- Plumbing fixed: `textureSampleLevel` → `textureLoad` (exact) for `dataTextureC` history read; `writeDepthTexture` now writes real `t / max_t` depth (was hardcoded zero).
- Naga: clean.

## gen-crystalline-mandala-bloom
- Kept verbatim: kaleidoscope-on-image mechanic, petal/ring SDF layer, all 4 param roles, ripple bloom.
- A packing: raw HDR display RGBA history, unchanged.
- Ideas in diff: `segIndex`/`facetHash`/`facetOffset`/`kFaceted` before the image sample (Idea 1); `edgeProximity`/`facetSparkle` block after the existing star sparkle (Idea 2).
- Plumbing fixed: none required — already fully plumbed.
- Naga: clean.

## gen-cosmic-slime-mold
- Kept verbatim: 6-seed `veinStructure` SDF network, growth-pulse timing, mouse-feeding mechanic, all 4 param roles.
- A packing: exact HDR temporal history, unchanged.
- Ideas in diff: `hasGrowthMemory`/`growthMemory` read near the top of `main()`, `+ growthMemory * 0.01` added to `growth` inside the vein loop, `matureGlow` block in the vein loop (Idea 1+2 combined mechanism), single-writer update block (`global_id.x == 0u && global_id.y == 0u`) at the end of `main()` writing `extraBuffer[133]`.
- Plumbing fixed: removed a shadowed duplicate top-level `"params"` JSON key (hyphenated `color-shift`, dead — the real one is the second `"params"` array with `color_shift`, left untouched).
- Naga: clean.

## gen-cosmic-velvet-hypnosis (second pass)
- Kept verbatim: spiral/octave-well math, drag-torque mouse mechanic, palette, params, ripple halos, both existing ideas.
- New ideas in diff: `runner2`/`counterPhase` (counter-runner comet), `runnerCollision` (crossing flash), `seamGlint` (runner × seamLip interaction). Folded into the `hdr` accumulation and `structure` (alpha) terms.
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
- Kept verbatim: warpedFbm spike mechanic, turingBand shell carving, mouse-repulsion field, core/shell split, params, ripple spike-boost. extraBuffer untouched (file documents it uses none).
- New ideas in diff: `bandAtHit`/`circuitGlow` (Turing-band circuit trace) and `pulseRaw`/`pulsePhase`/`signalPulse` (outward treble-keyed signal pulse), both added inside the `marchRay` hit branch right after `coreEmission`/`col` are computed.
- Plumbing fix: header previously had a "Batch 36 — Algorithmist / By: Kimi Agent" attribution stamp instead of a proper `Ideas:` line — normalized to the standard 7-line banner. Provenance preserved in git history and the JSON `description` field.
- A packing: unchanged — A/C = raw HDR display RGBA history.
- Gate: naga OK, precommit gate OK.

## gen-chrono-voronoi-mycelium (second pass)
- Kept verbatim: multi-generation Voronoi growth, nutrient/clickSurge mechanics, velocity-advected HDR history/flow field, the pre-ACES-in-A / ACES-on-writeTexture packing (left exactly as-is, not normalized to match the other 9 files), params, both existing ideas (clamp connections, apothecia cups).
- New ideas in diff: `myceliumBranch` return type changed from `vec2<f32>` to `vec3<f32>` to expose `rebirthFlash`; `cyclePeriod`/`cycleRaw`/`cycleT` replace the old one-shot `birthTime` age curve with a wrapped per-cell clock (cyclic regeneration); `rebirthGlow` accumulates `rebirthFlash` per generation and is composited as a green spark, folded into `color`, `alpha`, and `depth`.
- A packing: unchanged and explicitly preserved per the Idea Card's FORBID clause.
- Gate: naga OK, precommit gate OK.
