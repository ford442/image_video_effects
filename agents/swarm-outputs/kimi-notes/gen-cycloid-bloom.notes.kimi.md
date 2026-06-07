# gen-cycloid-bloom — Kimi Notes

## Changes
- Chromatic dispersion per petal layer: outer layers tinted red-shifted, inner blue-shifted.
- Deeper audio integration: `bass` modulates gear-ratio effective multiplier, `treble` adds sparkle.
- Enhanced feedback burn-in via `dataTextureC` with UV jitter for organic motion trails.
- Mouse orbit pulls bloom center; `dataTextureA` persistence stores frame state.
- Improved alpha semantics: glow intensity drives alpha rather than hardcoded 1.0.

## Wow-Factor
- 5 nested Spirograph layers with prismatic color separation create a spinning glass flower.
- Audio gear-ratio modulation causes petals to appear/disappear rhythmically.

## Risks
- 240 steps × 5 layers = 1200 distance evaluations per pixel; already borderline for low-end GPUs.
- Chromatic separation adds minimal cost but UV offsets must stay within valid range.
