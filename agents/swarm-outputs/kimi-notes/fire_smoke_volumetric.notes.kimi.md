# fire_smoke_volumetric — Kimi Notes

## Changes Made
- Added chromatic temperature gradient (R hot core → B cool smoke edges).
- Added temporal smoke persistence via `dataTextureC` blend (`prevSmoke * 0.92`).
- Added audio-driven turbulence enhancement (`turbulence *= (1 + bass * 0.3)`).
- Fixed semantic alpha with volumetric transmittance-based blending.

## Wow Factor
- Temperature color shift makes fire feel physically grounded.
- Smoke trails persist organically across frames.
- Bass drives turbulence for reactive flame flicker.

## Risks for Claude Polish
- Simplified noise (single hash call) may look blocky; consider fbm for turbulence.
- `dataTextureC` persistence may accumulate errors over long runtimes.
- Alpha blending with `mix(baseColor.a, 1.0, effectAlpha * 0.7)` may over-saturate.
