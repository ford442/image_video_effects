# Simulation leftover ten — coordinator review

Contract: `docs/SHADER_UPGRADE_BATCH.md` §9. Pass/fail per file against Idea Cards written in BRIEFS.md before WGSL.

| ID | Card | Ideas in WGSL | KEEP VERBATIM | Overlay? | A packing | Params | Springs | Naga |
|---|---|---|---|---|---|---|---|---|
| sim-decay-system | yes | veinPhase; oxideBloom | yes | no | raw decay/material/corrosion/protection | exact | none new | pass |
| sim-decay-system-rgba | yes | flakeMask; rustBleedIn | yes | no | raw paint/metal/organic/structure | exact | none new | pass |
| alpha-erosion-terrain | yes | fanDeposit; incision | yes | no | raw height/water/sediment/erosion | exact | none new | pass |
| alpha-crystal-growth-phase | yes | sideArm; grainBound | yes | no | raw phase/temp/orientation/impurity | exact | none new | pass |
| alpha-fire-temperature | yes | vortAmt; spark | yes | no | raw fuel/temp/smoke/age | exact | none new | pass |
| alpha-em-field-simulation | yes | lic loop; recombine | yes | no | raw Ex,Ey,B,charge | exact | none new | pass |
| alpha-multi-state-ecosystem | yes | ecotone; stain | yes | no | raw s1/s2/resource/toxin | exact | none new | pass |
| cellular-automata-rgba | yes | taxis; deathBloom/soilPatch | yes | no | raw plants/herbivores/predators/nutrients | exact | none new | pass |
| lenia-on-video | yes | pStretch; membrane | yes | no | raw density/neighborhood/growth/vidLuma | exact | none new | pass |
| digital-moss | yes | fromShade; thread | yes | no | raw grown/moisture/spores/age | exact | none new | pass |

Checklist (all ten):
- [x] Idea Card exists and was written before the diff
- [x] Each numbered idea is pointable in the WGSL
- [x] KEEP VERBATIM still holds
- [x] Diff is not ≥70% header / ACES / spring / ripple boilerplate
- [x] No generic overlay shared across the batch
- [x] A packing matches how C is read (raw sim)
- [x] Saved `params` unchanged
- [x] Springs/ripples only if native (HEAD click/held kept)
- [x] Naga + extraBuffer on this file

**Verdict: 10/10 pass.** Real-GPU visual QA remains external.
