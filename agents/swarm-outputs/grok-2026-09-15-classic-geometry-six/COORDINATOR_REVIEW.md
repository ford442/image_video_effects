# Coordinator review — classic geometry leftover six (2026-09-15)

Contract: `docs/SHADER_UPGRADE_BATCH.md` §9.

| ID | Card before WGSL | Ideas pointable | KEEP VERBATIM | Diff not boilerplate | Native not overlay | A packing | Params exact | Springs native | Naga |
|---|---|---|---|---|---|---|---|---|---|
| gen-3d-sierpinski-chaos | pass | repeatCorner; farIdx | pass | pass | pass | display RGBA | pass | none new | pass |
| gen-aperiodic-monotile | pass | chirality; brim | pass | pass | pass | display RGBA | pass | none | pass |
| gen-chromatic-zonohedron | pass | a3; win | pass | pass | pass | display RGBA (fixed lie) | pass | none | pass |
| gen-zeta-function-landscape | pass | zeroRail; isoContour | pass | pass | pass | display RGBA | pass | none | pass |
| gen-prismatic-mobius-helix | pass | seam; core | pass | pass | pass | display RGBA (fixed lie) | pass | none | pass |
| gen-voronoi-crystal | pass | f3 triple; L∞ mix | pass | pass | pass | display RGBA | pass | existing kept | pass |

**Batch: PASS 6/6.** Real-GPU visual QA remains external (no WebGPU adapter in this VM).
