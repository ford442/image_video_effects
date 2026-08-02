# Batch 23: `gen-fireworks-roman-candle`

- Fixed normalized mouse conversion with `p * resolution` before recentering.
- Kept held-fire behavior at the corrected cursor and added one-shot Roman
  candles for each guarded `ripples[]` event.
- Treble now raises trail, apex-spark, and click-glitter sample counts within
  bounded loops; bass remains launch energy/size.
- Replaced flat depth zero with tonemapped luminance-derived depth.
- Preserved the four existing parameter entries and the display-color feedback
  roles (`dataTextureA` primary, `dataTextureB` secondary).
- Metadata now truthfully advertises mouse, click, temporal, alpha, audio, and
  depth behavior.

