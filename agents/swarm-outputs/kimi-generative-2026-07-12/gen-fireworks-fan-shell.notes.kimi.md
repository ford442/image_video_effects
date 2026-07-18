# Optimizer Notes: gen-fireworks-fan-shell

## Key Performance / Pipeline Changes

- **Hex-bokeh glow** (`hexBokeh`) softens spark cores and reduces harsh point aliasing.
- **Early-exit star field** via `step(0.992, h)` keeps background cheap.
- **Single-sample temporal read** from `dataTextureC` with decayed persistence.
- **Depth pass-through** via `readDepthTexture` / `writeDepthTexture` each frame.
- **dataTextureA** stores bloom-weighted fan persistence for feedback.
- **Mouse-triggered personal fan** at cursor with gravity-fall spark trajectories.
- **Audio reactivity**: bass deepens shell energy; mids widen fan angle.
- **ACES tone map** + canonical 13-binding fireworks layout.

## Line Count Delta

- Original: ~102 lines
- Upgraded: ~169 lines
- Delta: +67 lines
