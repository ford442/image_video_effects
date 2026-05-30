# gen-psychedelic-layered-time-stamps — Kimi Notes

## Changes
- Chromatic channel splitting per distortion layer: R/G/B displaced by different bass-driven offsets.
- Audio-driven delay evolution: `mids` modulate distortion amplitude, `bass` drives layer accumulation rate.
- Depth compositing: reads `readDepthTexture` and scales layer contribution by depth value.
- Temporal feedback: `dataTextureC` read for delay history, `dataTextureA` written for persistent state.

## Wow-Factor
- 10-layer video echo with per-channel displacement creates liquid-chromatic smearing.
- Depth-aware compositing means foreground objects remain sharp while background dissolves into layers.

## Risks
- 10 texture samples per pixel plus depth read = 11 fetches; watch bandwidth on integrated GPUs.
- Feedback accumulation can saturate colors quickly if `bass` is high; gamma correction may be needed in Claude pass.
