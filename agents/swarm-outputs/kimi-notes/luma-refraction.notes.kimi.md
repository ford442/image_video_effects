# luma-refraction — Kimi Notes

## Changes Made
- Added semantic alpha (`clamp(0.8 + abs(h) * 0.05, 0, 1)` instead of raw sample).
- Added chromatic refraction offsets (R shifted by `treble`, B by `bass`).
- Added temporal wave damping memory via `dataTextureC` blend.
- Added audio-driven wave amplitude (`localSpeed *= (1 + bass * 0.3)`).

## Wow Factor
- RGB channels refract at different angles for chromatic water surface.
- Waves persist and evolve organically with temporal damping.
- Mouse clicks create bass-amplified ripples.

## Risks for Claude Polish
- Wave simulation uses simple laplacian; may need boundary clamping.
- `dataTextureC` read for both state and temporal blend is dual-purpose.
- Chromatic offsets may cause color fringing artifacts at high refraction.
