# Coordinator review — magnetic → neon ten

Cards were written in `BRIEFS.md` before the WGSL edits. Naga 10/10 on this batch.

| Shader | Ideas pointable | Kept | Overlay | Params | Packing | Verdict |
|---|---|---|---|---|---|---|
| gen-magnetic-field-lines | helix + mirror in the particle loop | dipole, LIC, X-point | no new spring | exact | display RGBA | pass |
| gen-magnetic-kelp | reconfig on width; meristem by bladder | cantilever, bladders | no | exact | display RGBA | pass |
| gen-magnetic-storm | chorus on `along`; plasmapause on `band_coord` | Alfvén, oval | no | exact | display RGBA | pass |
| gen-mandelbox-explorer | diagMin in orbit loop; interior mix | folds, DE, itinerary | no | exact | display RGBA | pass |
| gen-metaball-soft-body | film on bead; nephroid on normal | modes, beading | no | exact | display RGBA | pass |
| gen-micro-cosmos | cilia + vacuole in hit shade | march, fission, phase | no | exact | display RGBA | pass |
| gen-murmuration-phantom | long curl; vorticity eye | morph, banking, tau | no | exact | display RGBA | pass |
| gen-mushroom-mandala-garden | annulus; cap warts | gill tiers, Buller | no | exact | display RGBA | pass |
| gen-mycelium-network | clamp bow; septum + guttation | walk, autolysis, germ | no | exact | display RGBA | pass |
| gen-neon-acid-geometry | etch lip/undercut; cathode spot | SDFs, striae, titration | no | exact | display RGBA | pass |

Shared-overlay check: no spring, ripple stamp, or IQ palette was added. Existing ripples and the three prior extraBuffer writers (kelp 133, metaball 133, mycelium 133–135) were left as they were.

Real-GPU visual QA: external. This VM has no hardware GPU.
