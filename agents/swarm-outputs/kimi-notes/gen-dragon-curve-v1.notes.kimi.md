# gen-dragon-curve — Kimi Notes

## Changes
- Binary turn sequence dragon curve: each segment direction is determined by the classic paper-folding bit formula `((lsb << 1) & n) != 0`.
- Per-pixel brute-force trace of 256-512 segments with squared-distance early-out for neon glow rendering.
- Iteration-depth coloring: hue cycles from red (segment 0) through orange, green, blue, to violet (final segment).
- Turn intensity detection: compares consecutive turn directions to identify tight folds, boosting glow and alpha.
- Bass drives max segment count (256-512), creating more folds per frame as audio intensifies.
- Mouse zooms into curve detail by offsetting the evaluation coordinate.
- Depth controls effective line thickness perspective (depth = closer = thicker glow).
- Chromatic aberration on tight folds: R boosted, B attenuated at fold boundaries.
- ACES tone mapping for HDR neon glow.
- Temporal feedback via `dataTextureC` for motion trail persistence.
- Semantic alpha: `curve_density * turn_intensity * depth`.

## Wow-Factor
- Dragon curve rendered as a genuine space-filling fractal with neon HDR glow.
- Audio-reactive fold depth makes the curve breathe and expand with the beat.

## Risks
- 512 segment distance checks per pixel is compute-heavy (~2B ops at 2048x2048). Should run fine on discrete GPUs but may stress integrated graphics.
- Consider reducing `maxSeg` default if performance issues arise on low-end devices.
