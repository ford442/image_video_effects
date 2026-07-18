# gen-audio-reactive-quantum-pollen — creation notes (Batch 16, C1)

> kimi-cli timed out twice on this brief (420s, 0 bytes), so it was completed
> manually to the same creative brief on 2026-07-18.

## What was built
- Grain field: one hashed grain per grid cell, 3×3 neighborhood gather, 156 lines.
- Bass envelope (`bass_env` attack/release via `dataTextureC.r`) pulls grains onto a slowly-rotating log-spiral galaxy arm; mids drive per-grain harmonic orbits + hue shift; treble envelope fires scatter bursts.
- Mouse hold attracts nearby grains (smoothstep radial pull).
- Warped FBM haze backdrop with faint camera passthrough; treble adds auroral shimmer.
- Stack: `huePreserveClamp` → `acesToneMap` → centered IGN dither → premultiplied alpha.
- Alpha = `dens * (1.0 - depth*0.4) + haze*(1.0-depth)` per the brief's transmission-haze mandate.
- `dataTextureA` stores `bassEnv, trebEnv, dens, alpha` for next-frame envelopes.

## Validation
- `naga` OK; no banned tokens; `wgsl_precommit_gate` OK.

## JSON
- New def `shader_definitions/generative/gen-audio-reactive-quantum-pollen.json` (params: Grain Density, Glow Size, Orbit Speed, Hue Base).
