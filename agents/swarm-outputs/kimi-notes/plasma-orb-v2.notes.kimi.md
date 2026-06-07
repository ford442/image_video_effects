# plasma-orb v2 Upgrade Notes

## Summary
Upgraded from 93-line electric-arc orb to 139-line MHD plasma orb with tokamak field lines, Alfvén waves, magnetic reconnection, and synchrotron emission.

## Algorithmist Perspective
- Added divergence-free magnetic field B = curl(ψ) where ψ is a scalar potential.
- Alfvén wave perturbation propagates along B with audio-driven amplitude (mids).
- Tokamak toroidal-poloidal wrapping (q-factor) produces field line visualization.
- Magnetic reconnection events triggered by treble; flares computed via phase-matching.
- Equatorial current sheet added.
- Plasma beta = thermal / magnetic pressure computed for alpha.

## Visualist Perspective
- Synchrotron color mapping: blue (high energy) → red (low energy).
- Chromatic aberration on fast radial particles.
- HDR bloom on reconnection flares.
- ACES tone mapping on final composite.
- Temporal glow feedback via dataTextureC.

## Interactivist Perspective
- Bass drives plasma temperature (thermal pressure).
- Mids twist field lines (q-factor).
- Treble triggers reconnection flares.
- Mouse pinches orb (compression vector).
- Depth texture controls field line frequency (perspective density).

## Alpha Semantics
`alpha = plasma_beta × reconnection_intensity × depth + sheet × 0.3 + lineMask × 0.15`
Never uses opaque 1.0.

## Technical
- Lines: 139
- Naga: ✅ Valid
- No readTexture sampling.
- Uses dataTextureC for temporal feedback.
