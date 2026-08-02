# Batch 28: pixelation-drift

- Lines: 118 → 175 (+57).
- Made the previously dead mouse feature real with a sprung fine-pixel focus and held swirl; added click pixel rings, regional FFT drift/persistence, a bounds guard, and clamped chromatic/bleed sample coordinates.
- Preserved depth-driven pixel sizing and the temporal `dataTextureC` → `dataTextureA` display-history contract.
- Existing parameters are exact; additive click metadata, indexed `updatedParams`, and `supportsDepth` were added.
- Focused Naga/bind-group/extraBuffer gate: pass.
