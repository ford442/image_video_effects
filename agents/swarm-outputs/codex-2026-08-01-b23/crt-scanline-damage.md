# Batch 23: `crt-scanline-damage`

- Added guarded click bruises and localized degauss rings that refract the CRT
  sampling coordinates and briefly separate/desaturate phosphors.
- Wired the previously dead treble aggregate to sparse static snow and short
  horizontal scar bands.
- Preserved depth-aware barrel distortion, input alpha, source-depth pass-through,
  and temporal phosphor feedback in `dataTextureA`/`dataTextureC`.
- Added indexed `updatedParams` copied from the four existing `params` entries;
  the original IDs/defaults/ranges/steps remain untouched.

