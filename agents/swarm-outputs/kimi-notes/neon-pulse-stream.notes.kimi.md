# neon-pulse-stream — Kimi Batch B Notes

## What I Changed
- Added divergence-free curl-noise fluid advection so the background flows naturally under the neon streams.
- Implemented 3D tube Fresnel rim lighting: edges glow brighter than cores, giving the streams real volume.
- Treble now injects stochastic sparkle particles along high-luminance paths (thresholded `hash21`).
- Depth fades the tube intensity — background streams are dimmer, foreground streams are crisp.

## What I'm Proud Of
The Fresnel rim light on the tubes makes the neon feel like actual glowing glass rods rather than flat colored lines. The sparkle injection on treble hits creates genuine "firefly" moments.

## What Might Need a Human Eye
- The sparkle branch uses an `if (treble > 0.4)` — while acceptable, it could be rewritten branchless with `select()` if profiling shows divergence issues.
- `curl2D` + 3 texture samples + spark noise may be borderline for mid-tier mobile GPUs.
