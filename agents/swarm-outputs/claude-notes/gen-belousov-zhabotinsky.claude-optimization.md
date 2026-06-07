# gen-belousov-zhabotinsky — Claude Optimization (2026-06-07)

## Bottlenecks Identified
- Lines ~99-105: if/else color ramp with 3 branches — GPU warp divergence on every thread in transition zones
- Line ~127: `dataTextureB` never written — Laplacian fields discarded each frame
- No huePreserveClamp → orange-red wavefronts clip to white at high reaction rates
- Features list missing `aces-tone-map`

## Optimizations Applied
- Replaced 3-branch if/else color ramp with branchless smoothstep cascades: `t0/t1/t2 = smoothstep(...)` then sequential mix() — same visual result, no warp divergence
- Added `huePreserveClamp(col * 1.3, 2.0)` + IGN dither
- Write `lapA, lapB, oxidized, waveFront²` to `dataTextureB` — enables multi-scale read in a future coarse/detail pass
- Added `waveFront` to `dataTextureA.b` (was 0.0) — richer state for downstream reads
- Updated features and `Upgraded:` date

## Visual / Transcendence Notes
- Smoothstep ramp produces slightly softer color transitions between chemical zones vs the hard if/else — marginally more organic
- waveFront channel in dataTextureA.b means downstream shaders can drive effects from chemical activity without re-deriving it

## Remaining Risks
- Initialization logic (lines ~62-69) triggers when `a + b < 0.01` — this re-seeds from spiral every cold start, which is correct behavior; no change needed
- The `spiralTip` highlight (line ~109) uses a division by near-zero (`tipDist² + 0.001`) — acceptable as epsilon guard but could flash on exact center

## JSON Changes
- Added `aces-tone-map`, `hue-preserve-clamp`, `ign-dither` to features array
