# Coordinator review — distortion / warp ten (2026-09-08)

| ID | Card before WGSL | Ideas pointable | KEEP VERBATIM | Diff not ≥70% boilerplate | No generic overlay | A packing matches C | Params exact | Springs native | Naga |
|---|---|---|---|---|---|---|---|---|---|
| sine-wave | yes | nodes; Stokes | yes | yes | yes | telemetry kept | yes | none | pass |
| parallax-shift | yes | occlusion; CoC | yes | yes | yes | display RGBA | yes | none | pass |
| perspective-tilt | yes | vanish; Scheimpflug | yes | yes | yes | display RGBA | yes | none | pass |
| interactive-rgb-split | yes | split; lat/long | yes | yes | yes | display RGBA | yes | none | pass |
| radial-rgb | yes | radial CA; k3 | yes | yes | yes | display RGBA | yes | none | pass |
| elastic-surface | yes | Poisson; exact C | yes | yes | spectral was HEAD | raw disp/vel | yes | none | pass |
| vortex-distortion | yes | LIC smear; luma mix | yes | yes | overlay kept | raw vel field | yes | none | pass |
| chromatic-swirl | yes | angular CA; spin | yes | yes | yes | telemetry kept | yes | none | pass |
| infinite-zoom | yes | mouse pole; log wrap | yes | yes | yes | display RGBA | yes | none | pass |
| pixel-storm | yes | luma debris; exact C | yes | yes | yes | display RGBA | yes | existing eye | pass |

**Batch result: PASS (10/10 cards implemented).**

Gates: Naga 10/10, extraBuffer 0 new, dead sliders 0, catalog 1,361, `SKIP_WASM_BUILD=1` build green. Jest 652 pass / 6 fail (pre-existing WASM `bridge/api.js`).

Cloud-VM structural gates only. Real-GPU visual QA remains external.
