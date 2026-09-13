# Coordinator review — RD / predator-prey / nano leftover eight

Checklist per `docs/SHADER_UPGRADE_BATCH.md` §9.

| ID | Card before WGSL | Ideas pointable | KEEP VERBATIM | Diff not ≥70% floor | Distinct from siblings | A packing matches C | Saved params | Springs native | Naga + extraBuffer + dead sliders |
|---|---|---|---|---|---|---|---|---|---|
| reaction-diffusion | pass | anisoLap; mitosis | pass | pass | pass | raw U/V/packet/accum | exact | none added | pass |
| chromatic-reaction-diffusion-rgba | pass | overlap; warmSeed/coolSeed | pass | pass | not Marangoni clone | raw warm/cool UV | exact | none added | pass |
| alpha-reaction-diffusion-rgba | pass | taxis; membrane | pass | pass | not overlap-quench clone | raw warm/cool UV | exact | none added | pass |
| hybrid-reaction-diffusion-glass | pass | thickness; caustic | pass | pass | glass, not dual-species rewrite | raw chem/grad/caustic/coverage | exact | none added | pass |
| predator-prey | pass | neighbor drain; compost | pass | pass | discrete CA, not LV field | raw species/energy/age/variant | exact | none added | pass |
| predator-prey-rgba | pass | pursuit; flee | pass | pass | not CA-rgba plant-taxis | raw P/H/C/toxin | exact | none added | pass |
| nano-assembler | pass | dock; radial | pass | pass | display mosaic, not crystal sim | display RGBA | exact | none added | pass |
| nano-assembler-crystal | pass | snapped hex; recalescence | pass | pass | not dendrite/grain-boundary | raw phase/temp/orient/impurity | exact | none added | pass |

**Batch: PASS 8/8.**

Gates: Naga 8/8, extraBuffer 0 new `[0..132]`, dead sliders 0, catalog 1,364, SKIP_WASM_BUILD=1 build green. Jest 652 pass / 6 fail = pre-existing WASM `bridge/api.js` + canvas. Real-GPU visual QA: external.

Hygiene that was floor, not the upgrade: exact C loads on predator-prey / predator-prey-rgba / nano-assembler-crystal / hybrid laplacian; nano-assembler sampler names + `config.x` time; reaction-diffusion packing honesty; predator-prey-rgba Toxin Strength wired.
