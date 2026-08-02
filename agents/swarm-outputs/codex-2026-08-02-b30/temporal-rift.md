# Batch 30: temporal-rift

- Added the missing invocation guard, clamped chroma-history taps, and replaced the branchy history injection with a bounded mix.
- Added a sprung rift center in `extraBuffer[133..138]`, guarded click tears, and per-band FFT separation voices.
- The hue-preserving soft ceiling affects display only; A remains the existing clamped temporal history and depth remains pass-through.
- Source params are unchanged; additive metadata now marks click, audio, and temporal behavior while keeping `supportsDepth: false`.
- Final size: 120 -> 110 lines. Focused Naga, slider, buffer, JSON/list, Jest, and production-build checks pass.
