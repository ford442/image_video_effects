# gen-chromatic-vortex — Kimi Notes

## Changes Made
- Added temporal spiral drift via `dataTextureC` blend for angle persistence.
- Added chromatic sector dispersion: R/B sample at different sector offsets by audio.
- Added semantic alpha with depth attenuation and effect-strength blending.
- Added `dataTextureA` write with final color for downstream effects.
- Fixed hardcoded alpha=1.0 to dynamic value.

## Wow Factor
- Temporal drift makes the spiral feel organic and evolving.
- RGB channels map to different polar sectors for prismatic distortion.
- Audio drives sector count (bass) and hue rotation speed.

## Risks for Claude Polish
- `foldedTheta` computation uses same `sectors` for all channels; verify R/B offsets don't alias.
- Temporal blend (0.03 + bass*0.01) is very subtle.
- `yuv.z` reassignment on line 98 overwrites value used in previous line; verify correctness.
