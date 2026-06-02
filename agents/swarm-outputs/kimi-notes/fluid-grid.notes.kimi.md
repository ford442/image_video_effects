# fluid-grid — Kimi Batch C Notes

## What I Changed
- Replaced simple push-based grid distortion with divergence-free curl-noise flow field.
- Added `fbm`/`curl2D` chunk library for organic, non-divergent advection.
- Bass now drives both cell push strength and curl turbulence simultaneously.

## What I'm Proud Of
The grid lines now flow like actual fluid rather than just being pushed away from the mouse — you get little eddies and swirls that feel physically grounded.

## What Might Need a Human Eye
- `curl2D` samples fbm 4× per pixel — watch performance at 2048² on integrated GPUs.
