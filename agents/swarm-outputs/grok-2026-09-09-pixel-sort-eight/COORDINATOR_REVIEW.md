# Coordinator review — pixel-sort eight (2026-09-09)

Batch size 8 (Grok). Idea Cards in `BRIEFS.md` were written before WGSL.

| ID | Card | Ideas pointable | KEEP VERBATIM | Diff not ≥70% boilerplate | No cloned overlay | A packing | Params exact | Springs native | Naga + audits |
|---|---|---|---|---|---|---|---|---|---|
| pixel-sorter | pass | pass (`for i<=10`, `seam`) | pass | pass | pass | display RGBA | pass | 1-frame mouse delay only | pass |
| pixel-sort-explorer | pass | pass (`holdThresh`, `prevC`) | pass (scan sweep kept, not the upgrade) | pass | pass | display RGBA | pass | none | pass |
| spectral-flow-sorting | pass | pass (`textureLoad` LK, Asendorf walk) | pass | pass | pass | raw RGB A | pass | none | pass |
| hybrid-spectral-sorting | pass | pass (band Y walk, plasmaBuffer) | pass | pass | pass | display RGBA | pass | none | pass |
| flow-sort | pass | pass (LIC taps, interval gate) | pass | pass | pass | display RGBA (packing lie fixed) | pass | none | pass |
| magnetic-luma-sort | pass | pass (`tangent`, `domainGate`) | pass | pass | pass | display RGBA | pass | existing spring kept | pass |
| pixel-sort-radial | pass | pass (radial walk, `ringSeam`) | pass | pass | pass | display RGBA | pass | none | pass |
| mouse-pixel-sort | pass | pass (V/H walk, exact C) | pass (voronoi/attractor kept, not the upgrade) | pass | pass | display RGBA (telemetry lie fixed) | pass | none | pass |

**Verdict:** 8/8 pass. Structural gates: Naga 8/8, extraBuffer 0 new `[0..132]`, dead sliders 0, catalogs generated, SKIP_WASM_BUILD=1 build (see closeout). Real-GPU visual QA remains external.

**Fail if:** claiming the existing wavelength tint / scan sweep / IQ band palette / radial runners / De Jong costume as the upgrade. Those were kept; they are not the numbered ideas.
