# Batch 25: `scan-slice`

- Added a critically damped scanner head and guarded click-stamped independent
  slices at normalized ripple positions.
- Replaced general audio-buffer palette indexing with a procedural palette and
  valid per-slice FFT bins 1–8; previously unused mids/treble now light edges.
- Bounded stacked slice emission and made depth follow the selected displaced UV.
- Preserved the seven-slice search, display-in-A role, and all source parameters;
  added indexed `updatedParams` plus click/depth metadata.
