# data-moshing-diffusion — Kimi Notes

## Changes Made
- Added audio reactivity: bass drives smear strength, mids kappa, treble dt and quantize.
- Added chromatic anisotropic diffusion: each channel diffuses with different coefficient scaling.
- Added temporal smear persistence via `dataTextureC` blend for offset memory.
- Fixed semantic alpha with diffusion coefficient + offset magnitude.
- Added `dataTextureA` write with offset data.

## Wow Factor
- RGB channels smear at different rates for chromatic oil-paint drips.
- Audio drives corruption intensity for reactive glitching.
- Temporal persistence lets smears accumulate organically.

## Risks for Claude Polish
- `currentR/G/B` updated in-place during diffusion loop; order-dependent.
- `paintBoost = 1.0 + smearStrength * 0.3` then `mix(x, x, paintBoost)` is no-op; should be `mix(center, current, paintBoost)`.
- Chromatic diffusion coefficients may cause color channel divergence over iterations.
