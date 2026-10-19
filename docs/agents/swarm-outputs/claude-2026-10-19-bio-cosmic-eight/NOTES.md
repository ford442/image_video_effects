# Claude bio-cosmic-eight — Notes

2026-10-19. Eight generative shaders. Prelude migration (7 files: all except
gen-chrono-mycelial-tapestry, which already used it) ran first via
`scripts/migrate_to_prelude.py` and is header-only.

| Shader | Kept verbatim | A packing | Ideas in the diff |
|---|---|---|---|
| interactive_neural_swarm | hash placement, O(N²) pairing, spring [133..137], click fronts, HSV ramp, sliders | ACES display RGB + max activation in A.a (C unused) | `[idea 1]` myelin nodes + saltatory hop (`MYELIN_NODES`, `hopIdx`); `[idea 2]` bouton flare (`boutonPos`, `arrival`); `[idea 3]` dendritic spines (`SPINE_COUNT` loop). Floor: Reinhard → ACES, alpha 1.0 → network coverage |
| cosmic-jellyfish | map() SDF, camera, click wave, cosine palette, trail feedback, ACES + clamp | HDR trail RGB + trail alpha (unchanged) | `[idea 1]` thickness probe `transmit`; `[idea 2]` `gonadDensity()` sampled along the continuing ray; `[idea 3]` rhopalia `rimBand`/`blink`. Glow palette block moved above shading so the bell can transmit it (same values) |
| gen-quantum-fluorescent-aether-moth-swarm | all four 2026-09-27 ideas, curl2, spawn, feedback | raw HDR RGB + semantic alpha (unchanged) | `[idea 5]` `eye_ring`/`pupil` ocelli; `[idea 6]` `dust` glints deposited into the advected HDR trail |
| gen-chrono-mycelial-tapestry | myceliumLayer, 3 generations, knots, beads, max-trail | HDR display RGB + coverage alpha (unchanged) | Idea 3 `cordCore`/`cortex` rhizomorph; Idea 4 `aged` sepia drift of C before the max |
| gen-quantum-mycelium | fold/repeat lattice, 4 prior ideas, repulsion sphere | ACES display RGBA (C unused) | Idea 5 `dHook` clamp capsule; Idea 6 `g_compartment` → `compLit` stepping pulse |
| supernova-core | blackbody/OkLab, Sedov, decay, rays, spring companion, alpha compositor | premultiplied ACES display RGBA (C unused) | `[idea 1]` echo loop; `[idea 2]` `shadowCone`/`ejectaPass` on shells, RT, cells; `[idea 3]` `rsRing` reverse shock × `rtFingers` |
| gen-sentient-void-silk-nebula | curl field, braid, knots, palette, vortex, A/C blend | ACES display RGBA (unchanged) | Idea 3 `dew` beads; Idea 4 `voidMask`/`voidRim` |
| gen-aurora-silk | wind warp, ribbons, satin/threads/crease, grading chain | ACES display RGBA (unchanged) | IDEA 4 `rayLobe`/`rayFlicker`; IDEA 5 `hem` |

Saved `params` unchanged in every definition. JSON: description sentence appended;
`upgraded-rgba` added to interactive_neural_swarm, cosmic-jellyfish, gen-chrono-mycelial-tapestry
(ACES present in WGSL and ideas implemented). No new springs or ripples; no extraBuffer slots added.

Gates (Cloud VM): naga-wasm 8/8, wgsl_precommit_gate 8/8, audit:extrabuffer PASS,
audit:dead-sliders PASS (0 new), shader lists regenerated, Jest / lint / `SKIP_WASM_BUILD=1` build — see PR.
Real-GPU visual QA: external, not done. Thresholds for the void pockets (tension 0.05–0.17) and the
jelly gonad density are tuned by reading the code and need a look on a GPU.
