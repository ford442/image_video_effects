# quantum-ghost v2 Upgrade Notes

## Algorithmist Perspective
- Added Gaussian wave packet spreading via `gaussianWavePacket()` with time-dependent drift and sigma
- Interference patterns from two overlapping wave packets with different momenta
- Entanglement correlation lines drawn perpendicular to mouse direction, pulsing with time
- Quantum number glow (n=1,2,3) cycles with phase-dependent neon colors
- Partial measurement certainty modulates fringe visibility

## Visualist Perspective
- Ghost copies now have phase-dependent opacity via wavefunction amplitude
- Neon quantum numbers (cyan, magenta, blue) pulse at different frequencies
- HDR bloom on measurement events via `entangleGlow * 3.0` boost
- ACES tone mapping applied to final composite
- Chromatic separation now scales with momentum uncertainty (`uncertaintySpread`)
- Depth attenuation enhanced: near objects ghost less strongly

## Interactivist Perspective
- Bass drives wave packet delocalization (increases `uncertaintySpread`)
- Mouse click performs "measurement", collapsing ghosts (`measurementCertainty` jumps to 1.0)
- Depth controls uncertainty spread (shallower = more delocalization)
- Mids add cyan/magenta fringe tint, treble modulates fringe frequency

## Alpha Strategy
Alpha = `wavefunction amplitude * measurement_certainty * depth`
- Wave amplitude from interference term
- Measurement certainty from mouse/depth
- Depth as final modulator

## Lines
Upgraded from 91 lines to ~138 lines.

## Naga Status
PASSED — validation successful.
