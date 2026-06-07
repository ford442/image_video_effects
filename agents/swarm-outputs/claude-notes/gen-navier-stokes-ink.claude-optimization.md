# gen-navier-stokes-ink — Claude Optimization (2026-06-07)

## Bottlenecks Identified
- Line ~109: `textureStore(dataTextureA, ...)` written but `dataTextureB` never written — pressure field absent
- Divergence correction (`div * 0.5` subtracted from both velocity components) is not a proper projection — single-pass stub at best
- No huePreserveClamp → ink highlights clip to grey under saturation
- Features list missing `aces-tone-map` despite using it

## Optimizations Applied
- Added pressure stub: one Jacobi-style estimate `pressureEst = -div * 0.25` with gradient components written to `dataTextureB.rgba` — `(pressureEst, ∂p/∂x, ∂p/∂y, |vel|)` — enabling a future dedicated pressure-solve pass to read from dataTextureC
- Added `huePreserveClamp(col * 1.5, 2.0)` before ACES → ink deep blues stay saturated instead of whitening
- Added IGN dither after ACES
- Updated features list and `Upgraded:` date

## Visual / Transcendence Notes
- Pressure gradient in dataTextureB enables future divergence-free velocity correction pass without restructuring the main shader
- Velocity magnitude stored in dataTextureB.a is useful for downstream motion-blur or depth effects

## Remaining Risks
- Pressure stub is a single-pass estimate, not a converged Jacobi solve — velocity field remains slightly divergent at high injection rates; acceptable visually but physically approximate
- `dt = 0.7` is hardcoded — at high resolution or low framerate this could produce instability (CFL condition); could be made framerate-adaptive

## JSON Changes
- Added `aces-tone-map`, `pressure-stub`, `hue-preserve-clamp`, `ign-dither` to features array
