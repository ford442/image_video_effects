# Idea Card — gen-liquid-neon-cyber-metropolis

```
SHADER: gen-liquid-neon-cyber-metropolis
IDENTITY: an orbiting aerial view over an infinite repeated grid of dark concrete towers with KIFS crowns, wrapped in
  pulsing neon-vein shells that accumulate volumetric glow, with a pointer gravity warp bending the city apart.
KEEP VERBATIM: map() (gravity warp radius 12 x6, cell repetition, hashed tower heights + audio extrusion, box tower,
  4-iter KIFS crown, neon shell with sin(q.y*14) ripple, smin floor, material pick), calcNormal, orbit camera + mouse
  offset, 160-step 0.75 march with neon glow accumulation, concrete diffuse/amb + radial scan lines, neon hue ramp
  cyan->magenta, concrete sky spec, global bloom, fog. Param roles: x Neon Intensity, y City Density,
  z Audio Reactivity, w Gravity Warp Strength (UI labels Intensity/Speed/Scale/Mouse Influence unchanged).
EXISTING IDEAS: none named (first idea pass).
ADD:
  1. Liquid neon rivers — bright packets of neon flow DOWN each tower's vein shell (per-tower phase from the cell hash,
     speed lifted by bass) and pool as a glowing apron where the vein meets the ground. Native: the description is
     "rivers of hyper-luminescent liquid neon"; today the veins only pulse in place.
  2. Wet-street neon reflections — ground hits cast a short glossy reflection march that re-accumulates the same neon
     glow term the primary march uses, rippled by a cheap puddle normal. Native: liquid neon city at night = wet
     asphalt mirroring the veins; reuses map()/glow accumulation, no new material.
  3. Warp horizon lensing ring — where the gravity warp's 12-unit radius edge lies on the ground, a thin neon event
     horizon ring glows (strength = Gravity Warp slider, mids shimmer). Native: makes the existing pointer warp
     readable instead of adding a new cursor.
FORBID: spring cursor, u.ripples shockwaves, IQ cosine palette, conveyors, different city layout/fractal,
  the generic applyGenerativePrimaryControls shim (removed: shared intensity/speed/contrast shim is below floor),
  dataTextureB.
A PACKING: display RGBA (ACES + gamma) in A. C read as colour history via exact textureLoad for a light neon
  persistence trail (neon-only, bounded).
```
