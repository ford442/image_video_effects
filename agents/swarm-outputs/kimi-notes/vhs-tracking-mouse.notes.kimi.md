# vhs-tracking-mouse — Kimi Batch B Notes

## What I Changed
- Expanded from a single tracking bar to a full VHS degradation suite: tracking wobble, horizontal hold instability, chroma bleed with per-channel offsets, scanline dropouts, tape hiss/grain (IGN dither), vignette darkening, and treble-triggered tracking-loss white flashes.
- Chroma bleed now samples R/G/B at different horizontal offsets proportional to bar intensity.
- Added `ign_noise` for film-grain-style dithering on the noise channel.

## What I'm Proud Of
The tracking-loss flash on treble spikes genuinely feels like a VCR losing sync. The combination of horizontal hold wobble + chroma bleed + dropout creates an authentic analog degradation aesthetic.

## What Might Need a Human Eye
- The flash is triggered by `treble > 0.75` with a random gate — may be too rare or too frequent depending on audio analysis smoothing.
- Scanline dropouts use a hard threshold (`step(0.96, dropoutNoise)`) which can flicker aggressively; consider softening.
