# emergent-calligraphic-weave v2 Upgrade Notes

## Summary
Upgraded from 104-line orientation-field strokes to 146-line Sumi-e brush dynamics simulation with Bézier sampling, ink viscosity, paper absorption, dry-brush texture, and chromatic edge darkening.

## Algorithmist Perspective
- Brush dynamics: pressure = mouseDown × noise, speed = bass-driven, viscosity = mids.
- Bézier stroke sampling: quadratic offset via perpendicular curvature modulated by velocity.
- Paper grain and fiber visibility scaled by depth.
- Capillary bleed computed from sampled vs current density difference.
- Evaporation term simulates faster/drier strokes from bass.

## Visualist Perspective
- Sumi-e ink wash palette with red/blue mix controlled by treble.
- Dry-brush texture modulates stroke via paper grain smoothstep.
- Chromatic edge darkening: yellowing at ink boundaries detected by neighbor gradient.
- Paper fiber overlay adds tactile realism.
- ACES tone mapping.

## Interactivist Perspective
- Bass drives brush speed (faster = drier strokes).
- Mids control ink concentration and viscosity.
- Treble adds splatter via stochastic threshold.
- Mouse acts as brush; pressure approximated by mouseDown state.
- Depth scales paper grain frequency.

## Alpha Semantics
`alpha = ink_density × paper_absorption × depth + splatter × 0.5`
Never uses opaque 1.0.

## Technical
- Lines: 146
- Naga: ✅ Valid
- No readTexture sampling.
- Uses dataTextureC for temporal stroke feedback.
