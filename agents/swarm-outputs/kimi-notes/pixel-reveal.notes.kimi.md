# pixel-reveal — Kimi Batch C Notes

## What I Changed
- Added per-channel chromatic aberration to pixelated blocks (R/G/B sample at slightly different UVs inside each block).
- Depth now controls pixel block size: foreground = finer pixels, background = coarser blocks.
- Audio treble injects sub-pixel jitter that makes blocks shimmer.

## What I'm Proud Of
The chromatic pixelation makes the transition zone between clear and pixelated look like a broken LCD screen — each RGB subpixel is physically separated.

## What Might Need a Human Eye
- The jitter on treble can make text unreadable during bass drops — verify this is desirable.
