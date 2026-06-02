# luma-melt-interactive — Kimi Batch B Notes

## What I Changed
- Replaced simple vertical gravity melt with a full 2D curl-noise flow field (divergence-free advection via `curl2D`).
- Added depth-aware viscosity: foreground (high depth) melts slower and pools; background runs fast.
- Mouse heat trails are now amplified by treble glow and bass-driven turbulence.
- Added `hash21` / `valueNoise` / `fbm` chunk library for the curl field.

## What I'm Proud Of
The curl noise makes the melt genuinely spiral and pool instead of just falling straight down. When you hold the mouse still during bass, you get little vortices that feel like actual liquid metal cooling.

## What Might Need a Human Eye
- `curl2D` samples fbm 4× per pixel — could be heavy at 2048² on integrated GPUs.
- The viscosity mapping assumes depth=1.0 is foreground — verify this matches the depth model convention.
