# electric-contours v2 Upgrade Notes

## Algorithmist Perspective
- Added electric field line tracing from charge distributions
- Two fixed charges + mouse-controllable charge with `potentialAt()` and `fieldAt()`
- Equipotential surfaces via `abs(sin(potential * density))`
- Field line density via angular sampling of field vector
- Dielectric boundary conditions approximated via depth-based displacement modulation

## Visualist Perspective
- Plasma-like glow on field lines via `edge_color * glow_multiplier * field_contrib`
- Dielectric polarization colors shift between green (low mids) and orange (high mids)
- HDR bloom on high-field regions via corona discharge approximation
- ACES tone mapping on final composite with bloom addition
- Edge detection (Sobel) combined with field contribution for richer contour lines

## Interactivist Perspective
- Bass modulates charge magnitudes (`q1`, `q2` scale with bass)
- Mouse click adds/removes charge (`mouseCharge` toggles on mouseDown)
- Depth controls field line density perspective (farther = denser lines)
- Mids drive spark intensity and dielectric color shift

## Alpha Strategy
Alpha = `field_line_density * dielectric_displacement * depth`
- Field line density from field magnitude
- Dielectric displacement from field contribution
- Depth as perspective weight

## Lines
Upgraded from 95 lines to ~146 lines.

## Naga Status
PASSED — validation successful.
