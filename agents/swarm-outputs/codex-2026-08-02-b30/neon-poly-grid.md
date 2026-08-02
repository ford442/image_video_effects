# Batch 30: neon-poly-grid

- Added a sprung touch focus in `extraBuffer[133..138]`, guarded click trail rings, and per-cell FFT neon voices.
- Replaced undefined reverse smoothsteps, applied a display-only hue-preserving ceiling, and now emits honest grid/trail relief depth.
- Preserved A as the raw scalar temporal trail `(trail, 0, 0, trail)` and kept source compositing recognizable.
- Source params are unchanged; audio/click/temporal/depth metadata and indexed `updatedParams` are additive.
- Final size: 121 -> 161 lines. Focused Naga, slider, buffer, JSON/list, Jest, and production-build checks pass.
