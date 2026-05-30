# kinetic-dispersion — Kimi Batch C Notes

## What I Changed
- Added curl-noise displacement to block scatter for organic dispersion patterns.
- Audio bass now triggers radial shockwaves from the mouse position.
- Depth scales scatter intensity (background disperses more than foreground).

## What I'm Proud Of
The shockwave on bass drops sends a visible ring through the scattered blocks — it turns a static glitch effect into a rhythmic one.

## What Might Need a Human Eye
- The `curl2D` approximation uses `hash12` instead of smooth fbm — faster but noisier.
