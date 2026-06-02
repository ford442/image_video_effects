# holographic-projection-failure v2 Upgrade Notes

## Overview
Upgraded from ~93 lines to 153 lines. Category: retro-glitch.

## Algorithmist Changes
- Added phase wrapping errors: `wrappedPhase = fract(phase / TAU) * TAU` with wrap error highlights.
- Bit-depth truncation via `bitTruncate()` (posterization from 8→3 bits).
- Block corruption with variable block sizes tied to corruption intensity.
- Cascading failure modes triggered by bass thresholds (desync, corruption, drift).

## Visualist Changes
- Cyan/magenta holographic color separation with temporal drift.
- Scanline desync with horizontal jitter and V-hold offset per scanline band.
- Chromatic aberration amplified by drift and depth parallax.
- Ghost image from frame offset during drift.
- ACES tone mapping.
- Static noise overlay.

## Interactivist Changes
- Bass triggers three failure modes: desync (>0.65), corruption (>0.55), drift (>0.45).
- Mouse repairs projection within 0.22 radius when down.
- Depth controls projection plane distance (parallax scaling).

## Alpha Strategy
`alpha = stability * (1.0 - failure_intensity * 0.5) * depth + staticOverlay * 0.3`

## Params Mapping
- instability (x) → baseInstability (failure probability scaler)
- chromatic_split (y) → chromaticSplit (R/B channel shift)
- scanline_drift (z) → scanDrift (V-hold jitter)
- signal_noise (w) → staticNoise (grain overlay intensity)

## Validation
- naga: PASSED
- workgroup_size: changed from (8, 8, 1) to canonical (16, 16, 1)
