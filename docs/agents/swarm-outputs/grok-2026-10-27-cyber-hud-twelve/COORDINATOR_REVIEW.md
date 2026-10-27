# Coordinator review — cyber HUD twelve (2026-10-27)

Cards were written before the idea edits. Each numbered idea is commented in the WGSL. Saved `params` are unchanged. Soft inverse-square (§12.2F) is only on `neon-edge-radar`. Paint tangent (§12.2C) is only on `cyber-trace`.

| Shader | Result | Formula | Notes |
|---|---|---|---|
| oscilloscope-overlay | pass | none | Flyback blank; phosphor tail from C.a. |
| energy-shield | pass | none | Facet shade; impact desaturates the photo. Trail packing kept. |
| laser-burn | pass | none | Neighbour heat; oxide lip. Raw state kept. Display is ACES. |
| neon-edge-radar | pass | soft inverse-square (§12.2F) | Wake, rings, and hold kept. Speckle is the second idea. |
| data-stream | pass | none | Leading head; column dropout. |
| quantum-cursor | pass | none | Stair boundary; bright collapse. |
| signal-tuner | pass | none | Sync bar; chroma swim. Snow, ghost, and beats kept. |
| cyber-lattice | pass | none | Solder joints; far rail occluded. A is pre-ACES. |
| cyber-trace | pass | stroke tangent (§12.2C) | Groove and via dashes. History RGB kept. |
| cursor-aura | pass | none | Core spend; penumbra bleach. |
| neon-strings | pass | none | Inharmonic partials; sympathetic neighbour. Nodes and pins kept. |
| cyber-hex-armor | pass | none | Gap shadow; hinge pin. A is pre-ACES. |

Checklist: mechanism interrogation is in `BRIEFS.md`. No shared spring stamp. Naga 12/12. extraBuffer 0 new. Dead sliders 0 new. Real-GPU visual QA was not run.
