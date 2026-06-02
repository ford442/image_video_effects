# gen-de-jong-attractor — Kimi Notes

## Changes
- Chromatic parameter separation: R channel accumulation uses a+b parameter bias, B uses c+d bias, creating color topology.
- Audio morph speed: `bass` expands parameter amplitude for more extreme geometric warping.
- Depth from density: accumulated attractor density drives `writeDepthTexture` for downstream depth effects.
- Temporal accumulation enhanced with hueOff drift for palette evolution.

## Wow-Factor
- Same attractor, two color topologies — red lace vs blue lace woven from the same math.
- Audio amplitude expansion reveals hidden fractal structures at extreme parameter values.

## Risks
- 128 iterations with dual-channel accumulation is ALU-heavy; consider 96 iterations on low-end.
- Parameter amplitude expansion can push values outside bounded regions; `amp` clamp limits this.
