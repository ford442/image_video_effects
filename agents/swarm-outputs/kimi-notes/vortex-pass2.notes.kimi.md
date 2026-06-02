# vortex-pass2 — Kimi Notes

## Changes Made
- Added chromatic velocity blur offsets (R trail shifted by treble, B by bass).
- Added temporal vorticity accumulation via `dataTextureC` blend.
- Added audio-driven swirl intensity (`swirlStrength *= (1 + bass * 0.3)`).
- Refined iridescent curl-based tint with HSV cycling.

## Wow Factor
- RGB velocity trails streak in different directions for chromatic fluid motion.
- Vorticity accumulates temporally for persistent swirl memory.
- Bass pumps swirl strength for reactive fluid dynamics.

## Risks for Claude Polish
- Pass 2 assumes velocity data in `readTexture`; verify Pass 1 output format.
- Chromatic blur loops may be expensive (`blurSteps` up to 6 iterations).
- `dataTextureC` blend factor (0.06 + mids*0.02) may be too subtle.
