# Coordinator review — print / paint / convolution ten (2026-09-08)

Fail the file if any box is unchecked.

| ID | Card before WGSL | Ideas pointable | KEEP VERBATIM | Diff not ≥70% boilerplate | No generic overlay | A packing matches C | Params exact | Springs native | Naga |
|---|---|---|---|---|---|---|---|---|---|
| conv-non-local-means | yes | luma SSD; tangent search | yes | yes | yes | display RGBA | yes | none added | pass |
| conv-anisotropic-diffusion | yes | Tukey; coherence axis | yes | yes | yes | display RGBA | yes | none added | pass |
| conv-difference-of-gaussians-cascade | yes | XDoG; zero-cross | yes | yes | yes (palette was HEAD) | display RGBA | yes | none added | pass |
| conv-morphological-erosion-dilation | yes | black-hat; skeleton | yes | yes | yes | display RGBA | yes | none added | pass |
| conv-gabor-texture-analyzer | yes | quadrature; dom-θ grain | yes | yes | yes (palette was HEAD) | display RGBA | yes | none added | pass |
| watercolor-bloom | yes | granulation; backrun | yes | yes | yes | display RGBA | yes | none | pass |
| film-cross-process | yes | per-ch grain; XPro highs | yes | yes | enlarger spring was HEAD | display RGBA | yes | kept HEAD | pass |
| engraving-stipple | yes | roulette; taper | yes | yes | yes | telemetry A kept | yes | none | pass |
| rotoscope-ink | yes | ink weight; cel hold | yes | yes | yes | telemetry A kept | yes | none | pass |
| encaustic-wax | yes | wax bloom; iron scrape | yes | yes | yes | telemetry A kept | yes | none | pass |

**Batch result: PASS (10/10 cards implemented).**

Gates: Naga 10/10, extraBuffer 0 new, dead sliders 0 (focused 10 + full-tree 0 new), catalog 1,361, `SKIP_WASM_BUILD=1` build green. Jest 652 pass / 6 fail (pre-existing WASM `bridge/api.js`).

Cloud-VM structural gates only. Real-GPU visual QA remains external.
