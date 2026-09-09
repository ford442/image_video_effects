# Coordinator review — wet media / charcoal / ink / paint ten

Pass/fail per file against Idea Cards in `BRIEFS.md`.

| ID | Card before WGSL | Ideas pointable | KEEP VERBATIM | Diff not overlay | Packing | Params | Springs native | Naga+audits |
|---|---|---|---|---|---|---|---|---|
| charcoal-rub | yes | fiberUV / vineDust | yes | yes | A.r mask | exact | none (HEAD none) | pass |
| charcoal-rub-diffusion | yes | vineStroke / kneadSkip | yes | yes | A.r mask | exact | none | pass |
| alpha-paint-thickness | yes | knifeRidge / weave | yes | yes | pigment+thick | exact; z/w wired | none | pass |
| ink-diffusion | yes | fiberDir / nijimi | yes | yes | ink/vel | exact | none | pass |
| sim-ink-diffusion | yes | laplacian fiber / ring | yes | yes | U+V | exact; visc wired | none | pass |
| ink-bleed-fluid | yes | valley / wetRim | yes | yes | vel/p/ink | exact | none | pass |
| mouse-paint-splatter | yes | satMask / dryCrack | yes | yes | paint+wet; (0,0) stash | exact | none | pass |
| alpha-fluid-simulation-paint | yes | densGrad / spec | yes | yes | vel/p/dye | exact | none | pass |
| alpha-watercolor-wetness | yes | cockleUV / salt | yes (granulation kept, not the upgrade) | yes | pigment+water | exact; w wired | none | pass |
| artistic_painterly_oil | yes | scumble / prevBody mix | yes | yes | pre-ACES + thick | exact | none | pass |

**Batch: PASS 10/10.**

Floor: Naga 10/10, extraBuffer 0 new, dead sliders 0, catalog 1,362, SKIP_WASM_BUILD=1 build green. Real-GPU visual QA: external.
