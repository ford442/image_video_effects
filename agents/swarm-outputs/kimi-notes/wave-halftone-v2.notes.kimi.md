# wave-halftone v2 Upgrade Notes

## Overview
Upgraded from ~92 lines to 150 lines. Category: image.

## Algorithmist Changes
- Replaced uniform grid with hexagonal close-packed dot grid (`hexCell`, `hexCenter`).
- Added 2D wave interference from multiple oscillators (sine+cosine superposition).
- Wave equation modulates dot radius at interference nodes.

## Visualist Changes
- Moiré patterns at high-interference nodes.
- Chromatic aberration on wave crests (R/B channel split).
- Paper texture grain via hash noise.
- ACES tone mapping on final composite.
- Depth-based perspective scaling (smaller dots for distant objects).

## Interactivist Changes
- Bass drives wave amplitude multiplier (`1.0 + bass * 1.5`).
- `ripples` array acts as dynamic wave sources when mouse is down.
- Mouse cursor generates continuous wave emission.
- Depth texture controls dot perspective.

## Alpha Strategy
`alpha = interferenceIntensity * dotDensity * depth + mask * 0.12`

## Params Mapping
- size (x) → dotSizeScale (0.4–1.2)
- density (y) → gridDensity (12–92)
- amp (z) → waveAmp (0–0.15)
- speed (w) → chromaticAmt (0–0.02) — renamed to Chromatic Aberration

## Validation
- naga: PASSED
- workgroup_size: (16, 16, 1)
