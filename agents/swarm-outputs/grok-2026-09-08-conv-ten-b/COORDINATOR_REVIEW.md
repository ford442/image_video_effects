# Coordinator review — convolution ten B (2026-09-08)

| ID | Card before WGSL | Ideas pointable | KEEP VERBATIM | Diff not ≥70% boilerplate | No generic overlay | A packing matches C | Params exact | Springs native | Naga |
|---|---|---|---|---|---|---|---|---|---|
| conv-guided-video-filter | yes | depth guide; exact C | yes | yes | yes | display RGBA | yes | none | pass |
| conv-stochastic-stipple | yes | paper; ellipses | yes | yes | yes | display RGBA | yes | none | pass |
| conv-structure-tensor-flow | yes | minor LIC; luma tint | yes | yes | palette was HEAD | display RGBA | yes | none | pass |
| conv-spiral-blur | yes | φ arms; Archimedean | yes | yes | yes | display RGBA | yes | none | pass |
| conv-steerable-pyramid | yes | h2 energy; source mix | yes | yes | palette was HEAD | display RGBA | yes | none | pass |
| conv-reaction-convolution | yes | C.rg persist; Pearson | yes | yes | A,B,blue kept | A,B,blue | yes | none | pass |
| conv-guided-filter-depth | yes | luma range; photo hold | yes | yes | yes | display RGBA | yes | none | pass |
| conv-bilateral-grid-splat | yes | depth range; bin slice | yes | yes | yes | display RGBA | yes | none | pass |
| conv-frequency-domain-notch | yes | oriented; residual cut | yes | yes | palette was HEAD | display RGBA | yes | none | pass |
| conv-fractal-kernel | yes | boundary; glint | yes | yes | palette was HEAD | display RGBA | yes | none | pass |

**Batch result: PASS (10/10 cards implemented).**

Gates: Naga 10/10, extraBuffer 0 new, dead sliders 0, catalog 1,361, `SKIP_WASM_BUILD=1` build green. Jest 652 pass / 6 fail (pre-existing WASM `bridge/api.js`).

Cloud-VM structural gates only. Real-GPU visual QA remains external.
