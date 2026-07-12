# mouse-ink-bleed — Interactivist upgrade notes

- **What changed:** Added domain-warped FBM turbulence for organic ink flow, a temporal feedback trail via `dataTextureC`/`dataTextureA`, an audio envelope on bass, depth-aware fog darkening, ACES tone mapping, and IGN dither. The JSON now declares `upgraded-rgba`, `temporal-persistence`, and `depth-aware`, and maps four params to `zoom_params.x/y/z/w`.
- **Why:** The original ink effect was static per-frame; injecting temporal persistence and audio-reactive envelopes makes the bleed feel alive and painterly, while depth-aware compositing keeps it slot-chain friendly.
- **Performance concern:** Three `fbm(..., 3)` evaluations per pixel for the curl-like displacement; acceptable for medium-complexity but keep an eye on mobile GPUs. The trail blend adds only two extra texture samples.
