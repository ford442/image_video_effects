# Coordinator review — glitch twelve (2026-10-27)

Cards were written in `BRIEFS.md` before the WGSL edits. Each numbered idea has a `// ── Idea` comment. Saved params were not renamed or re-defaulted.

| Shader | Verdict | Formula rows | Notes |
|---|---|---|---|
| scanline-tear | pass | sync-pulse (§12.2B), chroma delay (§12.2B) | Both sit inside the existing H-sync and burst paths. Defaults of those two sliders are 0, so the ideas show when those sliders move. |
| vhs-jog | pass | none | Head-switch bar and flag skew. Cue bars, pause flutter, and reverse phase stay. |
| vhs-tracking-mouse | pass | none | Adjacent-track slip and overscan bar. Dashes, lock, and AGC stay. Centred X keeps the bar shut. |
| strip-scan-glitch | pass | none | Slit taps are source samples. The C streak and the brake stay. |
| sliding-tile-glitch | pass | none | Grout uses one unshifted sample. Restoration is now distance-weighted; the slider still damps slide. |
| data-stream-corruption | pass | dwell (§12.2C) | Head/tail on the existing column. A stays the corruption field. C is an exact load. |
| rgb-split-glitch | pass | none | Hanging dots and crawl. Angle Offset is still the temporal chroma mix. A and B packing unchanged. |
| digital-compression | pass | DCT quantization (§12.2B) | AC step is gated by Bit Crush. Mosquito uses the existing edge. A stays the diagnostic. |
| interactive-glitch-brush | pass | speed-thinning (§12.2C) | Grenades keep the base radius. Block snap uses the existing block scale. |
| interactive-glitch | pass | Schmitt (§12.2B) | Latch is A.a. Display alpha stays coverage. Scan packet uses the block row. |
| interactive-glitch-cubes | pass | none | Bevel and side wall use the existing height. A.a stays settled height. |
| glitch-cathedral | pass | none | Cames, pointer split, and row sort. Cell Size 20 and Pattern Speed 0.5 match the previous quant and rose rate. The three dead sliders are read. |

Formula check: no §12.2 row is used on more than one file. No new spring. No shared IQ palette. ACES is on the display write; stored sim and delay fields are not tone-mapped.

Real-GPU visual QA: not run. This VM has no hardware GPU.
