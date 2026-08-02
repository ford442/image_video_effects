# Batch 30: color-channel-weave

- Rewired dead reserved-zone audio reads from `extraBuffer[0..2]` to canonical `plasmaBuffer[0].xyz`.
- Added spring warp tilt in `extraBuffer[133..138]`, guarded click pluck waves, and per-cell FFT yarn specular voices.
- Replaced undefined reverse smoothsteps, reused one source-depth sample, and emits weave relief while preserving display A and diagnostic B packing.
- Source params are unchanged; click/depth metadata and indexed `updatedParams` are additive.
- Final size: 122 -> 158 lines. Focused Naga, slider, buffer, JSON/list, Jest, and production-build checks pass.
