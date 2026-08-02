# Batch 30: voxel-depth-sort

- Fixed the soft-shadow term so it darkens voxel tops instead of adding gray light.
- Added a sprung isometric view in `extraBuffer[133..138]`, depth-local click extrusion waves, and per-cell FFT rim shimmer.
- Preserved ACES display color, real relief depth, semantic alpha, and A-field packing `(luma, topMask, depthConf, alpha)`.
- Source params are unchanged; click/depth metadata and indexed `updatedParams` are additive.
- Final size: 120 -> 154 lines. Focused Naga, slider, buffer, JSON/list, Jest, and production-build checks pass.
