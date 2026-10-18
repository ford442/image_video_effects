# Coordinator review — photo-plane ten

Cards were in `BRIEFS.md` before the WGSL edits. Each numbered idea is marked `Idea 1` / `Idea 2` in the shader.

| Shader | Verdict | Notes |
|---|---|---|
| bismuth-crystallizer | pass | Rim and tarnish sit on the existing hopper loop. Sliders unchanged. No spring. |
| molten-glass | pass | Crust and drip use the heat field already advected from C. Stored heat is not tone-mapped. |
| circular-pixelate | pass | Diaphragm clips the existing dome. Grout is the hex boundary. Lenslet path kept. |
| spectral-mesh | pass | Beads and fringe are on the existing wires. A packing left as the mesh mask. |
| cross-conv-mouse-bilateral | pass | Coring is inside the bilateral weight. Wet edge is the brush falloff. Kernel size kept. |
| selective-color | pass | Hue window limits color inside the existing masks. Contour uses `boundary`. |
| plasma | pass | Filaments connect the same eight orbs. Corona reads photo luma. Pointer orbit is the already-claimed mouse feature, not a shockwave. |
| poincare-tile | pass | Ink is the existing sector boundary. Cusps use `q` from `getPolyParams`. Disk clip kept. |
| quantum-fractal | pass | Fringes use `atan2` of psi1. The photo sample moves with psi2. Iteration formula unchanged. |
| liquid-chrome-ripple | pass | Crest and trough compare the existing height samples. Chrome sheet and C history kept. |

No file shares a spring, ripple-shock, or IQ-palette overlay with the previous file. Saved params were not renamed or re-defaulted.

Real-GPU visual QA was not run.
