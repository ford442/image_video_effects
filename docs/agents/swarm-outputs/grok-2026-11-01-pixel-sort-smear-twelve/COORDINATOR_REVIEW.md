# Coordinator review — pixel-sort / smear twelve

Cards were written in `BRIEFS.md` before the WGSL edits. Each numbered idea has a `// ── Idea` comment in that shader's main path.

| Shader | Verdict | Why |
|---|---|---|
| glitch-pixel-sort | pass | Delay keeps sorted luma and lagged chroma, mixed by Glitch Amount. Dropout is one-sided behind the existing packet. fp128 sort, melt, and the RGB split stay. |
| pixel-sorter | pass | Ramp uses `steps` from the existing close. Comb is perpendicular to the existing axis and only inside the run. Asendorf and the seam stay. |
| pixel-sort-radial | pass | Spokes are the angle the radial walk already had. Inward pile uses Direction's existing 0.5 split; outward spend uses Stretch Amt. |
| pixel-sort-explorer | pass | Ticks and dust read `streakT` from the existing interval. Smoothness still sets stride. Hold and persist stay. |
| spectral-glitch-sort | pass | Shared step mixes toward the block hash the noise slider already owns. Tear bias uses the existing click energy and sort axis. Walk and chroma sort stay. |
| spectral-flow-sorting | pass | Confidence scales only the LK term. Barbs cross `flowDir`. A is still the raw photo for the next LK step. |
| hybrid-spectral-sorting | pass | Gutter sits on the band edge the walk already stops at. Band head reuses `best`. Palette and hue shift stay. |
| pixel-drag-smear | pass | Side taps leave the drag line. Drying is outside the brush; Decay still holds the stroke. No new spring. |
| pixel-stretch-interactive | pass | Cauchy shapes the existing chromatic reach; Chromatic Scale still sets ±0.5. Gutter uses coherence and a side-texel luma. Tensor stays. |
| luma-smear-interactive | pass | Uphill removal uses the luma gradient the downhill term already computes. Fringe desaturates from the existing R/B taps. Packing, including (0,0), stays. |
| spectral-smear | pass | Radius divides by the spring speed the file already stores. Hue advances along that same velocity. Palette stays. |
| quantum-smear | pass | Still regions mix the advected UV back to the pixel. The void lip sits on the existing potential. A stays pre-ACES so motion compares like quantities. |

Formula check: no §12.2 row is on more than one file. Cauchy is not shared with the explosion batch's blackbody file inside this batch. No shared spring, IQ stamp, or ripple stamp was added.

Plumbing: Naga 12/12, precommit gate 12/12, extraBuffer 0 new, dead sliders 0 new (full catalog re-scan), lists regenerated. Vitest 180 files / 1532 passed (1 skipped). `SKIP_WASM_BUILD=1 npm run build` succeeded. Saved params unchanged. Real-GPU visual QA is external.
