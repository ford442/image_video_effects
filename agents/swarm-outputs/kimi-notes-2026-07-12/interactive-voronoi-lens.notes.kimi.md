# interactive-voronoi-lens — Interactivist upgrade notes

- **What changed:** Added audio-reactive point jitter (bass envelope + treble speed), smooth-min second-distance cell edges for neon outlines, temporal trail accumulation via `dataTextureC`/`dataTextureA`, depth-aware fog, ACES tone mapping, and semantic alpha. The JSON adds `upgraded-rgba`, `audio-reactive`, `temporal-persistence`, and `depth-aware` features.
- **Why:** Voronoi lens distortion was under-reactive; the audio jitter and temporal trails give cells emergent, liquid motion while mouse proximity still controls focal strength.
- **Performance concern:** The 3x3 Voronoi search plus `smin` second-distance tracking is heavier than the original; at high `Cell Density` the per-pixel cost scales with cell count. The 9-cell loop remains the dominant cost.
