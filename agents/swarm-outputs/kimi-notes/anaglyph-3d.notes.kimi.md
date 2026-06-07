# anaglyph-3d — Kimi Notes

## Changes Made
- Added temporal ghost fringing persistence via `dataTextureC` blend.
- Added chromatic separation enhancement per depth (R boosted, G/B reduced at extremes).
- Refined mouse focal depth curve (`focalDepth = mix(mouseDepth, 0.5, 0.3)`).
- Added bass-pulsed split width enhancement.

## Wow Factor
- Ghost trails persist for temporal stereoscopic depth.
- Chromatic boost at depth extremes enhances 3D pop.
- Mouse focal point gives user control over convergence plane.

## Risks for Claude Polish
- Ghost persistence blend may accumulate into uniform red/cyan bias.
- Chromatic boost formula (`color.r *= (1 + chromaBoost)`) may clip highlights.
- Grain addition is subtle; consider making it more visible at high grain param.
