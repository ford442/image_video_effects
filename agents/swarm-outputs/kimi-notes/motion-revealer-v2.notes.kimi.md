# motion-revealer v2 Upgrade Notes

## Summary
Upgraded from 96 lines to ~125 lines. Added optical flow estimation via structure tensor, motion-compensated reveal, spectral chromatic aberration on motion trails, HDR glow on fast-moving objects, ACES tone mapping, and motion blur.

## Algorithmist Changes
- Structure tensor computed from live frame gradients (E, F, G).
- Eigenvector extraction yields optical flow direction.
- Motion magnitude from frame difference weighted by gradient energy.
- Motion confidence threshold inversely driven by sensitivity param.

## Visualist Changes
- Spectral chromatic aberration on motion trails (R/G/B sampled along flow with offsets).
- HDR glow on bright, fast-moving regions.
- ACES tone mapping for cinematic color.
- Motion blur via accumulation along flow direction.
- Live frame mixed at 30% for contextual grounding.

## Interactivist Changes
- Bass drives motion sensitivity threshold (`threshold = 0.03 / sensitivity`).
- Mouse creates a radial motion mask (paints motion even in static regions).
- Depth controls trail length (`maxTrail *= depthFactor`).

## Alpha Semantics
`alpha = motionConfidence * trailIntensity * depthFactor`
- Static regions = transparent.
- Confident motion with depth perspective = opaque.

## Parameter Mapping
| Slot | Param | Range | Default |
|------|-------|-------|---------|
| x | Motion Sensitivity | 0-1 | 0.4 |
| y | Trail Length | 0-1 | 0.35 |
| z | Glow Strength | 0-1 | 0.4 |
| w | Chromatic Separation | 0-1 | 0.3 |

## Validation
- naga: OK
- Category: interactive-mouse (unchanged)
- readTexture: sampled (image-based interactive shader)
