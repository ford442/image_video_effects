# Optimizer Notes: gen-fireworks-ring-shell

## Key Performance / Pipeline Changes

- **Hex-bokeh ring glow** softens expanding shell perimeter.
- **Early-exit background** star field keeps empty sky cheap.
- **Single-sample feedback** from `dataTextureC` with ring persistence decay.
- **writeDepthTexture** + **dataTextureA** written every frame.
- **Mouse opens personal ring shell** centered at cursor position.
- **Audio reactivity**: bass expands ring radius; mids boost chroma saturation.
- **Gravity-fall secondary sparks** after ring expansion phase.
- Canonical fireworks pipeline helpers and ACES output.

## Line Count Delta

- Original: ~107 lines
- Upgraded: ~170 lines
- Delta: +63 lines
