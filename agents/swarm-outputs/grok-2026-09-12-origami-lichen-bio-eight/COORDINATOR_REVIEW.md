# Coordinator review — origami / lichen / bio leftover eight

Checklist from `docs/SHADER_UPGRADE_BATCH.md` §9.

| File | Card before WGSL | Ideas pointable | KEEP VERBATIM | Diff not boilerplate | Distinct from neighbors | A packing matches C | Params exact | Springs native-only | Naga + extraBuffer + dead sliders |
|---|---|---|---|---|---|---|---|---|---|
| origami-fold | pass | buckle; print-through | pass | pass | pass (not wet-fold clone) | display RGBA | pass | none added | pass |
| interactive-origami-coupled | pass | capillary; Kármán | pass | pass | pass | raw vel/vorticity/dens | pass | mouse stash [133..134] only | pass |
| gen-lichen-reaction-diffusion | pass | thallus rings; apothecia | pass (noise regimes kept) | pass | pass (not moss rhizoids) | display RGB + density | pass (no params key; updatedParams kept) | none | pass |
| gen-bioluminescent-reaction-diffusion | pass | quench; excitation | pass | pass | pass (not this morning's RD) | raw A/B/age | pass | none | pass |
| nano-repair | pass | healing front; weld | pass | pass | pass | raw health | pass | none | pass |
| digital-moss-rgba | pass | territorial ridge; stalks | pass | pass | pass (not shade taxis) | raw ABCD | pass | existing spring kept | pass |
| bioluminescent | pass | tropism; quorum | pass | pass | pass | raw growth | pass | none | pass |
| bioluminescent-blackbody | pass | front heat; cooling lag | pass | pass (overlay stripped) | pass | growth+heat | pass | none | pass |

**Batch:** pass. Real-GPU visual QA: external.
