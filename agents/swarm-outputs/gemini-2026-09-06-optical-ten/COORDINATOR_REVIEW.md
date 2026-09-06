# Coordinator Review — Optical / Glass / Holographic Ten

Evaluation checklist and audit results against `docs/SHADER_UPGRADE_BATCH.md` §9.

| Shader | Card before diff | Ideas pointable | KEEP VERBATIM | Diff not overlay | Packing | Params | Springs only if native | Naga |
|---|---|---|---|---|---|---|---|---|
| `gen-holographic-lens-flare-matrix` | yes | `ghost1`/`ghost2`; `irisDiffraction`; `newtonColor` | yes | yes | raw sim | exact | none | pass |
| `gen-holographic-plasma-geode` | yes | `dispersedHolo`; `arcEmission`; `agateBands` | yes | yes | display | exact | none | pass |
| `gen-holographic-rainbow-surface` | yes | `marangoniColor`; `drainage`; `grooveSheen` | yes | yes | display | exact | none (surface tilt) | pass |
| `gen-holographic-data-core` | yes | `photonPulse`; `cageWire`; `moirePattern` | yes | yes | display | exact | none | pass |
| `gen-holographic-bismuth-core-reactor` | yes | `edgeGlint`; `multiOrderOxide`; `containmentFlux` | yes | yes | display | exact | none | pass |
| `chromatic-folds-bilateral` | yes | `foldR`/`foldG`/`foldB`; `depthWeight`; `resonanceDisp` | yes | yes | display | exact | none | pass |
| `aero-chromatics-prismatic` | yes | `vortexShedding`; `schlierenSample`; `decayR`/`decayB` | yes | yes | display | exact | none (smoke wind) | pass |
| `glass-shatter-morph` | yes | `microCracks`; `tirGlint`; `isochromaticFringe` | yes | yes | display | exact | yes (shard inertia) | pass |
| `frosted-glass-lens-iridescence` | yes | `dropRefract`; `wipeFactor`; `bevelDispersion` | yes | yes | display | exact | yes (glass lens) | pass |
| `spec-prismatic-dispersion` | yes | `causticColor`; `arSheen`; `streakHighlight` | yes | yes | display | exact | yes (physical lens) | pass |

**Pass.** Batch rigorously adheres to the incremental ideas contract:
- 10/10 Idea Cards written in `BRIEFS.md` before any code changes.
- 2–3 native optical/glass/holographic ideas implemented per shader in existing main path.
- Algorithm and identity preserved across all 10 effects.
- Saved preset parameter contracts byte-exact in JSON definitions.
- Exact-integer `textureLoad(dataTextureC, coord, 0)` previous-frame feedback on all effects.
- Springs limited exclusively to shaders that already own a moving lens/shard mass.
