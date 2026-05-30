# contour-flow — Kimi Upgrade Notes

## Changes
- Curl-noise flow field superimposed on edge-aligned advection
- Depth-based mixing: foreground sharper, background more advected
- Bass turbulence adds velocity to drift direction
- Treble sparks on Sobel edge intersections
- Per-pixel curl flow replaces uniform directional flow

## Wow Factor
- Edges appear to flow like ink in water, curling organically
- Depth separation creates parallax flow layers

## Risks
- Sobel + curl + advection = 7 texture samples per pixel
- Edge spark threshold may need tuning per source
