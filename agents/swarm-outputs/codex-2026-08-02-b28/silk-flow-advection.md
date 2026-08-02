# Batch 28: silk-flow-advection

- Lines: 118 → 173 (+55).
- Activated the previously ignored velocity history: `dataTextureC.xy` now temporally smooths live curl velocity before raw velocity state is written back to `dataTextureA`.
- Added a sprung, aspect-correct fabric finger, safe zero-length direction handling, click plucks, regional FFT weave shimmer, bounded velocity state, and nonnegative display emission.
- The silk/curl/advection identity, semantic alpha, honest flow depth, and source parameters remain intact; truthful click/depth metadata is additive.
- Focused Naga/bind-group/extraBuffer gate: pass.
