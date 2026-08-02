# Batch 28: spec-importance-sampled-bokeh

- Lines: 117 → 176 (+59).
- Added the missing invocation guard, a top-left-safe sprung focal point, cursor-depth focus matching, click focus rings, regional FFT brightness, and subtle hash-jittered golden-angle samples.
- Reused the sampled depth value and clamped semantic importance alpha while preserving the 48-sample importance-weighted bokeh core, ACES display map, and raw HDR `dataTextureA` color.
- Existing four parameter contracts are unchanged; `updatedParams` is an indexed mirror. Added truthful depth/audio/click features and `supportsDepth`.
- Focused Naga/bind-group/extraBuffer gate: pass.
