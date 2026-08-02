# Batch 30: x-ray-reveal

- Restored the canonical 16x16 workgroup, clamped Sobel taps, fixed the already-ranged lens-softness control, and made fractional contrast NaN-safe.
- Added a spring lens in `extraBuffer[133..138]`, guarded click X-ray pulses, and regional FFT edge voices.
- Added honest edge/ring relief depth and a hue-preserving display ceiling while keeping A as display RGBA.
- Source params, including mappings/descriptions, are unchanged; click/depth metadata and indexed `updatedParams` are additive.
- Final size: 121 -> 160 lines. Focused Naga, slider, buffer, JSON/list, Jest, and production-build checks pass.
