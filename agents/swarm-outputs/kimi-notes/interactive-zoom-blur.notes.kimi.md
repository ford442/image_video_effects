# interactive-zoom-blur — Kimi Notes

## Changes Made
- Added temporal blur trail persistence via `dataTextureC` blend.
- Added chromatic radial streak separation (R/B streak at different angles).
- Added depth-scaled blur attenuation (`strength *= (1 - depth * depthAttenuation)`).
- Refined dithered sampling with Bayer matrix.

## Wow Factor
- Blur trails persist for motion-streak effect.
- RGB streaks diverge radially for chromatic zoom blur.
- Deeper objects blur less, maintaining focus hierarchy.

## Risks for Claude Polish
- `blurSteps` loop (up to 35 iterations) may be expensive on mobile.
- Depth attenuation at `depth=1` may completely eliminate blur.
- Temporal blend may accumulate into uniform smear over time.
