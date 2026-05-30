# pixel-stretch-interactive — Kimi Batch B Notes

## What I Changed
- Added per-channel chromatic directional stretch: R stretches 1.5× farther than G, B shifts negatively, creating asymmetric color smear.
- Audio bass now elongates stretch length via `bass_env` multiplier applied to chroma intensity.
- Depth controls stretch magnitude: background stretches 40% more than foreground, creating a depth-based temporal dissolve feel.
- Cross-mode gets diagonal chromatic vectors instead of pure horizontal.

## What I'm Proud Of
During a bass drop the stretch elongates so far that the image becomes abstract streaks of pure color, then snaps back on the beat. The depth variation makes foreground subjects feel solid while backgrounds dissolve.

## What Might Need a Human Eye
- The directional chromatic shift uses 3 separate texture samples with different UV offsets — verify no seam artifacts at screen edges when `clamp()` is active.
- The `depthStretch` curve (mix 1.4 to 0.6) may need tuning for different depth model outputs.
