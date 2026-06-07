# gen-chaos-game-ifs — Kimi Notes

## Changes
- Temporal attractor drift: slow rotation of fixed points driven by `time`.
- Chromatic channel splitting per iteration depth: R/G/B use different attractor offsets, creating rainbow halos.
- Audio-reactive scale pulsing: `bass` modulates IFS contraction factor.
- Temporal ghosting: `dataTextureC` previous frame blended at 10–15% for persistent attractor trails.
- `dataTextureA` written for downstream access.

## Wow-Factor
- IFS attractor rotates and breathes with audio; the fractal feels alive rather than static.
- Chromatic per-channel offsets create a 3D anaglyph-like depth illusion without glasses.

## Risks
- Iteration depth up to 12 with 3 channel variants = 36 loop iterations; may be heavy on mobile.
- Ghosting accumulation can cause burn-in if feedback is high; `clamp` on alpha limits it.
