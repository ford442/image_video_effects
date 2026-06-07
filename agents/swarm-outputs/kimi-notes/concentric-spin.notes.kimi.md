# concentric-spin — Kimi Batch B Notes

## What I Changed
- Added per-channel chromatic orbital dispersion: R/G/B rings rotate at slightly different angular offsets, creating live rainbow separation.
- Bass now multiplies ring density (spawns more rings); treble compresses ring spacing.
- Added depth parallax shift to the ring center so the effect feels 3D.
- Replaced the old `treble * 0.2` alpha boost with a more nuanced gap-mask-driven alpha.

## What I'm Proud Of
The RGB separation is extreme enough to read as three distinct rings at a glance during fast rotation, then they visually "snap" back together when the audio quiets. It's a genuinely new behavior for this shader.

## What Might Need a Human Eye
- The chromatic separation uses 3 texture samples (R/G/B at different UVs) — acceptable but worth watching on bandwidth-limited GPUs.
- Parallax depth offset is small (±0.05) — may be too subtle on some displays.
