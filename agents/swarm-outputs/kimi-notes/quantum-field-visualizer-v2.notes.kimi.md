# quantum-field-visualizer v2 — Upgrade Notes

## Overview
Upgraded from ~85 lines to **134 lines**. Added complex wavefunction visualization, quantum interference, and measurement-collapse interaction.

## Algorithmist Changes
- Added Gaussian wave packet simulation with two-slit interference
- Real/imaginary parts computed from `psi = gauss * e^(i*phase)`
- Probability density = `|psi|^2` drives brightness
- Phase drives hue via HSV conversion
- Uncertainty principle implemented via time-dependent packet spreading (`spread = 1.0 + spreadRate * t`)
- Mouse acts as measurement operator, collapsing wavefunction locally

## Visualist Changes
- Hue from quantum phase, saturation from interference contrast
- HDR bloom on high-probability regions (`bloom = max(bri - 1.0, 0.0)`)
- ACES tone mapping on final composite
- Base image mixed with quantum visualization for grounding

## Interactivist Changes
- Bass drives wavefunction energy and collapse-event intensity
- Mouse proximity = measurement certainty (smoothstep radius)
- Depth controls uncertainty spread multiplier

## Alpha Strategy
`alpha = clamp(collapsedProb * 0.5 + measureCertainty * 0.3 + depth * 0.2, 0.05, 1.0)`
- Semantic: probability density × measurement certainty × depth
- Never hardcoded to 1.0

## Validation
- naga: ✅ PASSED
- workgroup_size: (16, 16, 1)
- Bindings: 13 exact canonical
