# neon-topology — Kimi Batch C Notes

## What I Changed
- Added audio elevation: bass creates phantom contour lines above actual depth.
- Added depth atmospheric haze that fades distant topo lines into fog.
- Treble adds color shimmer to neon lines.

## What I'm Proud Of
The phantom contours on bass make the terrain feel like it's breathing — mountains grow and shrink with the music while staying topologically coherent.

## What Might Need a Human Eye
- The haze fade (`exp(-depth * 3.0)`) may be too aggressive for shallow depth maps.
