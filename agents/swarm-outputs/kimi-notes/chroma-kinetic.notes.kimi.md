# chroma-kinetic — Kimi Upgrade Notes

## Changes
- Velocity chromatic aberration: R leads, B lags by audio amount
- Directional smear: 3-sample motion blur along velocity vector
- Audio split: bass → R lead, mids → G smear, treble → B lag
- Depth modulation: deeper pixels smear less
- Luminance-based distortion weight preserved from original

## Wow Factor
- Motion blur follows actual displacement direction
- RGB channels separate like a high-speed photograph

## Risks
- 6 texture samples per pixel (3 chroma + 3 smear) — heavy
- Smear can over-blur at high `strength`
