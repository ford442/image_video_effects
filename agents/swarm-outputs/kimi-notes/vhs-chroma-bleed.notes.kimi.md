# vhs-chroma-bleed — Kimi Batch E Notes

## Changes Made
- Added audio-reactive jitter: bass drives line dropout probability, treble adds micro-glitch offset
- Added depth-scatter: depth scales chromatic bleed radius
- Added chromatic flash during shifts: mids add warm color burst
- RGB channels sample from independently jittered UVs
- Temporal data write to `dataTextureA` for jitter history

## Wow Factor
- VHS effect now syncs to music — bass drops cause tracking loss exactly like real tape
- Depth-scatter makes distant objects look more corrupted

## Risks
- Line dropout (`step(1.0 - bass * 0.15)`) may be too aggressive; could reduce to `0.1`
- Micro-glitter amplitude scales with treble; high-treble tracks may look unstable
