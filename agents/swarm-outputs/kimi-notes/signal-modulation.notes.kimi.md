# signal-modulation — Kimi Batch C Notes

## What I Changed
- Added 8-band spectral visualization overlay on the signal waveform.
- Chromatic aberration now scales with signal strength and treble.
- Added noise floor (analog static) and depth attenuation.
- `huePreserveClamp` prevents color blowout on strong signals.

## What I'm Proud Of
The spectral band visualization makes the whole screen feel like an oscilloscope + spectrum analyzer combo — genuinely useful for audio visualization.

## What Might Need a Human Eye
- The 8-band simulation uses a single `bandNoise` hash per band — not real FFT data, but looks convincing.
