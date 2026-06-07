# neon-edge-glow v2 Upgrade Notes

## Overview
Upgraded from ~91 lines to ~130 lines. Added gas discharge tube simulation with accurate neon/mercury emission spectra, AC rectification flicker, electrode sputtering glow, atmospheric haze, and ACES tone mapping.

## Algorithmist Changes
- Added `neonSpectrum()` with Gaussian emission peaks approximating neon lines (red 640.2nm, yellow 585.2nm, plus secondary bands).
- Added `mercurySpectrum()` for mercury vapor secondary spectrum.
- AC rectification flicker: `abs(sin(time * acFreq))` with `pow(rectified, 0.7)` for realistic tube striation.
- Beat flicker: `step(0.7, bass) * 0.2 * sin(time * 20)` for power-surge spikes.

## Visualist Changes
- Accurate neon tube colors via spectral Gaussians instead of simple hue cycling.
- Electrode sputtering glow at tube ends with exponential falloff.
- Chromatic aberration on tube ends via R/B channel offset.
- Atmospheric haze: `exp(-depth * 2.0)` modulated by mids.
- HDR bloom on glow regions with ACES tone mapping.

## Interactivist Changes
- Bass drives AC flicker frequency: `acFreq = 60.0 + bass * 40.0` Hz.
- Mouse bends the virtual tube via sine-wave distortion of UV coordinates.
- Depth controls atmospheric haze amount on the glow.
- Edge detection still driven by Sobel, now audio-boosted.

## Alpha Strategy
`finalAlpha = clamp(tubeExcitation * intensity * depth, 0.25, 0.98)`
where `tubeExcitation = edgeMask * (flicker + 0.3) + glow * 0.5 + electrodeGlow * 0.2`
Semantic: more excitation on edges + stronger flicker + closer depth = more opaque.

## Naga Status
Validated with `naga` (see main report).
