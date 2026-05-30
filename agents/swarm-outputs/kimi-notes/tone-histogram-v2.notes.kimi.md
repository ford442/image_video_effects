# tone-histogram v2 Upgrade Notes

## Overview
Upgraded from ~92 lines to 145 lines. Category: post-processing.
Converted from multi-pass (2-pass atomic histogram) to single-pass local adaptive equalization.

## Algorithmist Changes
- Removed atomic histogram buffer dependency (incompatible with canonical `array<f32>` extraBuffer).
- Added per-pixel 3×3 sliding-window local statistics (`localStats()` computes mean and std dev).
- Adaptive contrast stretch: `targetStd / localStd` with clamped gain.
- Film-like S-curve with independent toe and shoulder rolloff (`filmCurve()`).

## Visualist Changes
- Split-tone shadows (cool blue) and highlights (warm amber).
- Layered film grain texture for analog feel.
- ACES tone mapping for cinematic output.
- Depth-driven haze removal.

## Interactivist Changes
- Bass dynamically increases histogram stretch target.
- Mouse creates local exposure zones (dodge/burn within 0.25 radius).
- Depth texture controls haze removal strength.

## Alpha Strategy
`alpha = tonalConfidence * localContrast * depth + 0.18`

## Params Mapping
- target (x) → Stretch Amount (adaptive gain target)
- contrast (y) → Toe Strength (shadow rolloff)
- saturation (z) → Shoulder Strength (highlight rolloff)
- psychedelic (w) → Haze Removal (depth-based dehaze)

## Breaking Changes
- Removed `multi-pass-1`, `histogram`, `auto-exposure`, `atomic-buffer` features.
- No longer requires `tone-histogram-apply` pass. The companion shader still exists but is unlinked.

## Validation
- naga: PASSED
- workgroup_size: (16, 16, 1)
