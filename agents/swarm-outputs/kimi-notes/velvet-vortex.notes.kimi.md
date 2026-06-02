# velvet-vortex — Kimi Batch C Notes

## What I Changed
- Audio mids now modulate spiral arm count in real-time.
- Added depth parallax to vortex center (shifts with depth).
- Replaced static velvet tint with bass/treble-reactive color channels.

## What I'm Proud Of
When mids build up, new arms spawn from the center and the whole spiral reorganizes — it feels alive rather than just spinning.

## What Might Need a Human Eye
- Arm count changes discretely (floor(mids * 4.0)) which can pop — consider smoothing.
