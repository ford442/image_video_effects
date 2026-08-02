# Batch 30: crt-phosphor-decay

- Restored the canonical 16x16 workgroup and clamped every five-tap halation sample at image borders.
- Added a top-left-safe spring cursor in `extraBuffer[133..138]`, bounded click phosphor blooms, and per-row FFT scan shimmer.
- Preserved the temporal phosphor display-history A/C contract and depth-weighted halation behavior.
- Source params are unchanged; click/depth metadata and indexed `updatedParams` are additive.
- Final size: 121 -> 152 lines. Focused Naga, slider, buffer, JSON/list, Jest, and production-build checks pass.
