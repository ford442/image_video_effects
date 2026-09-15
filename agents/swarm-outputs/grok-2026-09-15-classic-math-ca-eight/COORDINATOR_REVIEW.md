# Coordinator review — classic math / CA leftover eight (2026-09-15)

Contract: `docs/SHADER_UPGRADE_BATCH.md`. Cards in BRIEFS.md written before WGSL.

| ID | Card | Ideas pointable | KEEP VERBATIM | Overlay? | A packing | Params | Naga |
|---|---|---|---|---|---|---|---|
| gen-rgb-diffraction | yes | blaze + Airy | yes | no | display RGBA | exact | pass |
| gen-verlet-cloth-wind | yes | weft/warp + hem | yes | no | lattice raw / else display | exact | pass |
| gen-sierpinski-tetrahedron | yes | lamps + beads | yes | no | raw minTrap | exact | pass |
| gen-3d-sierpinski-chaos | yes | biased die + age hue | yes | no | display RGBA | exact | pass |
| gen-chromatic-zonohedron | yes | dichroism + stars | yes | no | display RGBA (lie fixed) | exact | pass |
| gen-quasicrystal-iridescence | yes | Bragg + phason | yes | no | display RGBA | exact | pass |
| gen-turing-morphogenesis | yes | ridges + seams | yes | no | display RGBA | exact | pass |
| gen-buddhabrot-aura | yes | trichrome + anti | yes | no | display RGBA | exact | pass |

No new extraBuffer springs. Tetrahedron extraBuffer[0..5] deleted. Chaos extraBuffer FFT / [133] deleted.

**Pass 8/8.** Real-GPU visual QA remains external (no WebGPU adapter in this VM).
