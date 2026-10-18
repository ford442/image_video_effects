# Notes — magnetic → neon ten (2026-10-10)

Second pass. September 14 ideas stayed in the main path. Saved `params` were not edited.
Bindings swapped to `#include "_prelude.wgsl"` (header-only). `Upgraded:` bumped for the new ideas, not for the include.

## gen-magnetic-field-lines
- Kept: dipole kernel, six sin²θ shells, 18 streaks, LIC, Jacobian X-point, mouse dipole, C trail.
- Added in the particle loop: cyclotron helix (radius shrinks with |B|); mirror pile-up where line radius pinches.
- A packing: ACES display RGBA. No new spring.

## gen-magnetic-kelp
- Kept: lanes, cantilever `s²(3−s)`, pneumatocysts, fronds, surge ripples, magnetic pull, extraBuffer[133].
- Added: Vogel reconfiguration narrows `organicWidth` and the strand edge as current speed rises; pale meristem band tip-ward of each bladder.
- A packing: ACES display RGBA.

## gen-magnetic-storm
- Kept: dipole + curl bands, Alfvén kink, 557.7/630 nm oval, SSC shocks.
- Added: plasmapause bunching of `band_coord` plus a radial ledge; whistler chorus beads whose tone rises along the field line.
- A packing: ACES display RGBA. No C history (same as before).

## gen-mandelbox-explorer
- Kept: boxFold, sphereFold, scale, DE lighting, steel/gold/violet itinerary, mouse rotation, held slice.
- Added inside the existing orbit loop: min distance to the (1,1,1) axis (spine). After itinerary: glassy mix when `itersRun` reaches `maxIter`.
- A packing: ACES display RGBA.

## gen-metaball-soft-body
- Kept: inverse-square field, l=2/l=3, neck beading, mouse gravity, env reflection, extraBuffer[133].
- Added: thin-film color on `abs(bead)`; nephroid crescent from `dot(normal, lightDir)`, scaled by Caustic Strength.
- A packing: ACES display RGBA.

## gen-micro-cosmos
- Kept: ellipsoid march, fission furrow, Zernike thickness, darkfield on held mouse, marine snow, click blooms.
- Added in the hit shade: metachronal cilium wave on the rim; contractile vacuole aligned to a per-cell direction, fill then systole. Both feed coverage.
- A packing: ACES display RGBA.

## gen-murmuration-phantom
- Kept: sphere/torus/wave/fbm morph, local curl, banking wave, marginal optical depth, C trail.
- Added: one long-wavelength curl before the local flow (stronger with cohesion); a vorticity-zero eye that cuts density so sky transmits.
- A packing: ACES display RGBA (C.rgb colour, C.a coverage). No new spring.

## gen-mushroom-mandala-garden
- Kept: polar caps, lamella + lamellula II/III, Buller's-drop lattice, mycelium, fairy ring.
- Added: annulus on the stipe at a breathe-scaled radius; hash warts on the cap (not another gill tier). Both added to structure alpha.
- A packing: ACES display RGBA.

## gen-mycelium-network
- Kept: culled segment walk, chemotaxis, autolysis, `germinate()`, pulses, kick slots 133–135.
- Added: clamp-connection bow every 5th segment inside the existing cull; septal dark walls plus a guttation bead from hypha age. Beads feed glow alpha.
- A packing: ACES display RGBA (rgb decayed light, a glow mass).

## gen-neon-acid-geometry
- Kept: triangle/hex/circle SDFs, smin morph, phToColor, striations, titration sigmoid.
- Added per shape: etch lip from `shapeDist` and an interior undercut shade on the fill; cathode spot anchored at arc = −π/2, hotter while the mouse is held.
- A packing: ACES display RGBA.
