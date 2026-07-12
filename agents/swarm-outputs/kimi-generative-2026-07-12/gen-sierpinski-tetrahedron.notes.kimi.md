# Algorithmist Notes: gen-sierpinski-tetrahedron

## Key Algorithmic Changes

- **Second-order domain-warped FBM** deepens view distortion beyond single-pass warp.
- **Curl-noise advection** steers projection coordinates for organic drift.
- **Worley cellular accent** (`worley2`) adds jewel-cave microstructure in voids.
- **Schlick Fresnel metallic sheen** on tetrahedron facets.
- **Spring-damper audio envelopes** in `extraBuffer[0..2]` smooth bass/mid/treble.
- **Click persistence** via `extraBuffer[3..5]` and `zoom_config.w` mouse-down.
- **IGN dither** reduces banding after ACES tone map.
- Preserved multi-orbit-trap coloring (vertex, edge, shell) and temporal feedback.

## Line Count Delta

- Original: ~197 lines
- Upgraded: ~262 lines
- Delta: +65 lines
