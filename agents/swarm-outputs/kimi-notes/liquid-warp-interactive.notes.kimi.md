# liquid-warp-interactive — Kimi Batch C Notes

## What I Changed
- Added divergence-free curl noise to the fluid advection for organic swirls.
- Depth now controls viscosity: foreground resists flow, background flows freely.
- Mouse click amplifies chromatic aberration for a "liquid lens" effect.

## What I'm Proud Of
The viscosity gradient makes the liquid feel like it has real substance — thick honey in front, thin water in back.

## What Might Need a Human Eye
- Curl + turbulence + chromatic aberration = 5 texture samples per pixel — could be heavy.
