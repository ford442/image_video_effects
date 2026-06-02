# gen-acid-lissajous — Kimi Notes

## Changes
- Chromatic split per strand harmonic: R leads phase, B lags, creating rainbow trails.
- Enhanced feedback burn-in via `dataTextureC` with animated UV drift for motion persistence.
- Depth-scaled glow intensity: `readDepthTexture` attenuates distant strands.
- Bass drives active strand count (7 + 2 bass-driven extras).
- `dataTextureA` persistence and improved alpha semantics.

## Wow-Factor
- Neon Lissajous tubes with per-strand chromatic offsets look like oscilloscope fireworks.
- Bass spikes add extra harmonic strands in real time — the pattern thickens on beats.

## Risks
- 180 samples × up to 9 strands = 1620 distance checks per pixel; among the heaviest in Batch F.
- Depth-scaled glow adds one extra texture fetch; monitor on integrated GPUs.
