# Coordinator review — lighting leftover ten

Batch: leftover lighting / neon / volumetric. Idea Cards in `BRIEFS.md` before WGSL.

| File | Card before WGSL | Ideas pointable | KEEP VERBATIM | Diff not boilerplate | No overlay stamp | A packing honest | params exact | Springs native | Naga + audits |
|---|---|---|---|---|---|---|---|---|---|
| neon-pulse-edge | yes | tangent tube; loadEdge | yes | yes | yes | raw edge field | yes | none | pass |
| sim-volumetric-fake-em | yes | beer; exbKick | yes | yes | yes | display RGBA; [133..134] mouse | yes | none (ripples kept) | pass |
| sim-volumetric-fake | yes | blocked; motes | yes | yes | yes | display RGBA | yes | none | pass |
| volumetric-god-rays | yes | luma occlude; sunDisk | yes | yes | yes | display RGBA (was raw accum) | yes | none | pass |
| neon-flashlight | yes | umbra/penumbra; specCatch | yes (JSON roles remapped in WGSL) | yes | yes | display RGBA | yes | none (click kept) | pass |
| neon-strings | yes | nodeDark; endPin | yes | yes | yes | display RGBA | yes | none | pass |
| neon-edges | yes | invSq; isotherm | yes (current wave kept) | yes | yes | display RGBA (was field pack) | yes | none | pass |
| neon-edge-glow | yes | darkSheath; 60Hz mains | yes | yes | yes | display RGBA (was field pack) | yes | none | pass |
| anamorphic-flare | yes | highlightGate; blueLine | yes | yes | yes | display RGBA | yes | none | pass |
| neon-echo | yes | textureLoad C; p7Tail | yes | yes | yes | raw persist in A | yes | none | pass |

**Verdict: 10/10 pass.** Real-GPU visual QA remains external.

Three Sobel files used different mechanisms (tube / isotherm+invSq / sheath+mains).
