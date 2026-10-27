# Idea Cards — Grok (`cursor/batch-12`, 2026-10-26)

Written before WGSL edits. Twelve ripple, ink, gravity, and particle shaders. Each card adds **two** new ideas. Earlier ideas stay. Saved `params` stay byte-exact. No shared spring, ripple stamp, or IQ palette.

Formula rule: a §12.2 row is used on at most one file here.

Eleven pasted headers are migrated to `#include "_prelude.wgsl"` as infrastructure (`mouse-ink-bleed`, `cyber-ripples`, `velocity-field-paint`, `echo-ripple`, `sim-decay-system`, `liquid-touch`, `gravity-well`, `interactive-pixel-wind`, `sim-heat-haze-field`, `black-hole`, `mouse-paint-splatter`). `pixel-explode` already includes the prelude. That swap is not the upgrade.

`black-hole` is tagged `upgraded-rgba` but has no ACES. ACES on the display write is floor, so the existing tag becomes true. It is not one of the two ideas.

---

## mouse-ink-bleed

IDENTITY: ink bleeds from the cursor through a domain-warped field, wicks along paper fibres, and leaves a dark tide line where it dries.
KEEP VERBATIM: Spread Radius / Turbulence / Trail Decay / Color Intensity; domain warp; cursor gravity well; click shockwave; fibre-weighted 4-neighbour wick; tide-line rim. A stays `(trail rgb, wet-ink amount)`.
MECHANISM:
- tactic 2: wet ink on paper skips the tooth and pools under a brush that stays still.
- tactic 3: `strand` and `newWet` are computed and then only tint. `isPress` only scales the instantaneous brush.
- tactic 6: both ideas write the same trail and wetness. No new channel.
ADD:
  1. Paper granulation — a stable tooth hash punches the wet deposit, so the bleed is speckled. Turbulence keeps its role and scales the tooth.
  2. Dwell pool — a held pointer inside the spread radius climbs `newWet` toward full, so a still brush darkens and feathers more than a passing one.
FORBID: a Gray-Scott field, a new spring, an IQ palette, stealing the wetness channel for audio.
A PACKING: `(trail rgb, wet-ink amount)`. ACES on display only.
FORMULA: paper granulation (§12.2C); dwell pressure (§12.2C). Only this file.

## cyber-ripples

IDENTITY: quantized rings around the cursor, pixel-blocked, with chromatic split, neon SDF rings, and click shocks.
KEEP VERBATIM: Ripple Speed / Block Size / Chromatic Aberration / Wave Density; `QUANT_STEP` radius quantizer; FBM warp; SDF rings; `audioPalette`; neon glow; bass envelope in A.a. A stays display RGB + bass envelope.
MECHANISM:
- tactic 1: the radius is quantized and the sine on it is still continuous, so the rings do not look stepped.
- tactic 3: `blockSize` pixelates position and is ignored by the chromatic offset, which is a smooth x shift.
- tactic 6: A.a is the bass envelope. Neither idea stores new state.
ADD:
  1. LED ring steps — the sine is floored into six brightness levels before it displaces, so the rings read as discrete bands. Wave Density still sets the count.
  2. Block-snapped chroma — when Block Size is on, the chromatic offset snaps to that same cell, so the split lands on block boundaries. Aberration still sets the distance; with Block Size at zero the offset stays continuous.
FORBID: a second palette, a spring, shockwaves beyond the click rings already here, Schmitt state in A.a.
A PACKING: ACES display RGB + bass envelope in A.a.
FORMULA: none. The dead `plasmaBuffer[band+1]` shimmer becomes a treble phase. That is a dead-bin fix, not an idea.

## velocity-field-paint

IDENTITY: a vorticity-confined velocity field that drags the photo into streamline streaks, stirred by the cursor.
KEEP VERBATIM: Dissipation / Brush Size / Force / Vort. Confinement; semi-Lagrangian self-advection; confinement from stored curl; 4-neighbour stencil; LIC streaks. A stays raw `(vel.x, vel.y, omega, speed)`.
MECHANISM:
- tactic 1: the momentum fetch is a single backtrace. The error of that step is computable from the same field.
- tactic 2: confinement assumes rotation. Where the neighbours are shearing, that force invents swirl the flow does not have.
- tactic 6: both ideas use the velocity and curl already stored. A is not repacked.
ADD:
  1. MacCormack momentum — one corrective backward step, clamped to the 4-neighbour range, so eddies stay sharp. Dissipation still damps.
  2. Strain gate — confinement is reduced where strain exceeds `|curl|`, and the existing chromatic shear widens there. The confinement slider still scales the force.
FORBID: a dye solver, an IQ palette, a spring, writing display colour into A.
A PACKING: raw `(vel.xy, omega, speed)`. ACES on display only.
FORMULA: MacCormack advection (§12.2D). Only this file.

## echo-ripple

IDENTITY: stacked click echoes with a thin-film wake and a gravity bowl under a held pointer.
KEEP VERBATIM: Frequency / Speed / Echo Decay / Strength; `echoWave`; held bowl; thin-film and bioluminescent harmonics; exact C advection. A stays `[mixed RGB, bass envelope]`.
MECHANISM:
- tactic 2: a later echo in a real room arrives later. These echoes share one speed and only differ by a phase.
- tactic 3: the loop adds signed echoes and throws away the sum of their absolute values, which is the cancellation.
- tactic 6: A.a stays the bass envelope. Cancellation is display-only.
ADD:
  1. Staggered echo delay — echo `i` travels at `speed / (1 + 0.28 i)`, so later rings lag and pile up. The Speed slider still sets the fundamental.
  2. Cancellation nodes — where the echoes' absolute sum is large and their signed sum is small, the picture desaturates. One echo alone does not.
FORBID: deep-water `tanh` dispersion (other ripple files own it), a new palette, a spring, storing the latch in A.a.
A PACKING: `[mixed RGB, bass envelope]`. ACES on display only.
FORMULA: none. The guarded `plasmaBuffer[1..4]` shimmer becomes a treble phase. Dead-bin fix, not an idea.

## pixel-explode

IDENTITY: the photo breaks into tiles that blast away from the cursor, tumble, cast shadows, and show a bevel.
KEEP VERBATIM: Intensity / Speed / Scale / Detail; neighbour search; wobble; spin; drop shadow; bevel; click detonations. A stays ACES display RGBA (C unread).
MECHANISM:
- tactic 2: a thrown chip is longer along its flight and loses the corner that faces the throw.
- tactic 3: `offset` is a direction and a length. Coverage tests a rotated square of uniform scale.
- tactic 6: no history. Both ideas only change coverage.
ADD:
  1. Throw stretch — an airborne tile lengthens along `offset` and keeps its width, so the blast reads as thrown chips. Still tiles stay square.
  2. Corner chip — the corner facing the throw is missing once the blast is strong, and the navy gap shows through that bite.
FORBID: a particle buffer, a fluid solver, a new palette, repacking A as velocity.
A PACKING: ACES display RGBA.
FORMULA: none.

## sim-decay-system

IDENTITY: corrosion eats the photo from edges, creeps by neighbour count, and paints rust veins plus oxide bloom. The pointer lays protection.
KEEP VERBATIM: decay rate / edge vulnerability / color shift / recovery; 8-neighbour decay count; five-stage mix; filiform veins; oxide bloom; mouse protection. A stays raw `(decay, material, corrosion, protection)`.
MECHANISM:
- tactic 2: real filiform corrosion runs along the edge, and pits nucleate in the metal away from edges.
- tactic 3: `edgeGrad.xy` is a direction. The neighbour count treats every neighbour the same. `materialType` never nucleates.
- tactic 6: both ideas write the existing decay channel.
ADD:
  1. Underfilm creep — on an edge, neighbours along the tangent count more than neighbours across it, so decay runs along the edge the veins already follow.
  2. Pitting — rare stable sites in mid material, off the edge and outside protection, nucleate decay. The decay-rate slider still sets how fast a pit grows.
FORBID: a fluid solver, an IQ palette, a spring, a new stored channel.
A PACKING: raw `(decay, material, corrosion, protection)`. ACES on display only.
FORMULA: none.

## liquid-touch

IDENTITY: a capillary sheet — height, vertical velocity, temperature — with curvature pressure, biharmonic waves, Marangoni flow, and a touch dent.
KEEP VERBATIM: viscosity / brush / refract / tint roles as wired (gamma, radius, optical, Marangoni); 13-point stencil; curvature force; biharmonic; coalescence; microfoam. A stays `(phi, velocity, temperature, merge)`. B stays the diagnostic curvature write this file already owns.
MECHANISM:
- tactic 2: a warm film domes, and a steep contact line sticks instead of sloshing through.
- tactic 3: `temperature` only tints and drives Marangoni along the surface. `interfaceDelta` is computed and used as a force weight, not as a pin.
- tactic 6: both ideas write the same height and velocity.
ADD:
  1. Thermal blister — temperature adds to the vertical velocity, so warm patches dome and cool patches sink. The tint slider still owns temperature coupling.
  2. Contact-line pin — where the sheet is steep and the velocity is already small, velocity is damped, so the wetting ring holds.
FORBID: a horizontal velocity channel, a second curvature formula, an IQ palette, tone-mapping A or B.
A PACKING: raw `(phi, velocity, temperature, merge)`. ACES on display only. B unchanged.
FORMULA: Boussinesq buoyancy (§12.2D), vertical only. Only this file.

## gravity-well

IDENTITY: a Schwarzschild lens at the cursor — photon ring, redshifted background, Doppler disk, far-side halo, Keplerian streaks.
KEEP VERBATIM: schwarzschild radius / disk extent / flare gain / lensing order; deflection; redshift tint; tilted disk; Doppler; Kepler streaks; far-side halo. A stays lensing fields. C unread.
MECHANISM:
- tactic 2: the inner disk should be dim inside the innermost stable orbit, with a bright lip at that orbit. Higher-order lensing is chromatic.
- tactic 3: `higherOrder` only thickens the deflection. One UV is sampled for the whole photo. `diskRadius` is never compared to `3 rs`.
- tactic 6: C is unread. Both ideas are display-only. A stays the same four fields.
ADD:
  1. ISCO lip — inside `3 rs` the disk dims (plunge); a thin bright ring sits on the orbit. Disk extent still sets the outer edge.
  2. Chromatic deflection — red and blue sample a slightly larger and smaller deflection. Lensing order scales the split. Green stays on the existing ray.
FORBID: copying the pinch-and-glow look of `black-hole`, a new disk palette, a spring, tone-mapping the stored fields.
A PACKING: lensing fields `(deflection/3, rings, diskMask, shadow)`. C unread.
FORMULA: none (the split is the existing higher-order deflection, not a prism Cauchy term).
AMENDMENT: the display write is ACES. Stored fields are not. ACES of zero stays zero, so the shadow stays black. The header already claimed `upgraded-rgba`.

## interactive-pixel-wind

IDENTITY: pixels blow from the cursor, brighter texels farther, with an upwind shadow, trails, and a chromatic split.
KEEP VERBATIM: Wind Strength / Turbulence / Trail Length / Color Shift; wind from the cursor relative to center; fbm curls; luma weight; upwind shadow. A stays ACES display RGBA.
MECHANISM:
- tactic 2: wind arrives in sheets, and it combs the surface into ridges across the flow.
- tactic 3: `gust` is an fbm already computed and only colours the streak. `windN` is a direction with no cross-axis.
- tactic 6: C is display history. Neither idea repacks it.
ADD:
  1. Gust sheets — the existing gust field gates the mean wind, so some bands of the picture are calm and others are in the blast.
  2. Transverse ripples — a small extra offset and a brightness ridge perpendicular to `windN`, like sand combed by the same wind. Strength still scales the amplitude.
FORBID: a fluid solver, a new palette (the cosine tint stays as it is), a spring, luma-weight changes.
A PACKING: ACES display RGBA (premultiplied, as HEAD writes it).
FORMULA: none.

## sim-heat-haze-field

IDENTITY: a temperature field that rises off the ground, plumes, and refracts the photo, with schlieren along the temperature gradient.
KEEP VERBATIM: temperature / convection speed / distortion / heat-source count; 3×3 diffuse; upward plume; schlieren along `∇T`. A stays raw `(temp, grad.x, grad.y, displacement mag)`.
MECHANISM:
- tactic 5: a hot layer on the ground folds the view back on itself (an inferior mirage). A schlieren knife-edge is signed: one side of the gradient is bright, the other dark.
- tactic 3: `grad` is stored and then only used as a length and a tangent. `uv.y` already means "near the ground" for the heat source.
- tactic 6: the mirage only changes the display sample. A stays the temperature field.
ADD:
  1. Inferior mirage — where the ground is hot, the sample folds across the hot layer. Distortion scales how far the fold goes; at zero distortion the photo is unflipped.
  2. Signed schlieren — `dot(grad, light)` brightens one side of a hot edge and darkens the other, on top of the existing blue streak.
FORBID: replacing the 3×3 box with a different stencil, a fluid solver, an IQ palette, tone-mapping the stored temperature.
A PACKING: raw `(temp, grad.xy, displacement mag)`. ACES on display only.
FORMULA: none.

## black-hole

IDENTITY: a pinch lens into a black horizon at the cursor, with frame-drag swirl, a point-reflected photon ring, and an accretion glow.
KEEP VERBATIM: Intensity / Speed / Scale / Detail as gravity, horizon radius, glow, and lensing width; chromatic pinch; frame drag; photon-ring mirror; disk turbulence and infall packets. A stays `(dist, radius, horizonMask, alpha)`. C unread.
MECHANISM:
- tactic 2: the photon orbit is a magnification spike, not only a mirrored band. Light at the horizon is redder and dimmer.
- tactic 3: `redshift` is a mix toward a very mild tint and is easy to miss. `radius * 1.5` is never drawn.
- tactic 6: C is unread. Both ideas are display-only.
ADD:
  1. Photon-orbit caustic — a thin bright ring at `1.5 ×` the horizon radius, outside the void. Glow still scales it.
  2. Horizon reddening — the existing redshift mix becomes a real loss of green and blue, plus a dimming, scaled by Intensity. Far from the hole the photo is unchanged.
FORBID: a Keplerian disk, an ISCO lip, the far-side halo (`gravity-well` owns those), a spring.
A PACKING: fields `(dist, radius, horizonMask, alpha)`. ACES on the display write only.
FORMULA: none.

## mouse-paint-splatter

IDENTITY: wet paint thrown from the cursor and from clicks, drying into craquelure, with cast-off droplets beside a fast stroke.
KEEP VERBATIM: splatter size / dry rate / spread / color intensity; `(0,0)` mouse stash; cast-off satellites; click splashes; craquelure. A stays `paint.rgb + wetness.a` except the mouse stash at `(0,0)`.
MECHANISM:
- tactic 2: a fast throw is a streak, not a bigger circle, and wet paint darkens at the wet rim.
- tactic 3: `mouseDelta` grows the brush radius and places satellites. The coverage test is still a circle. Neighbour wetness is averaged and the gradient is discarded.
- tactic 6: the rim darkens stored paint. The ellipse does not change packing.
ADD:
  1. Throw ellipse — the stroke-aligned radius keeps the speed growth this file already has; the cross-stroke width stays near the size slider. A still brush stays a circle.
  2. Wet-edge rim — where neighbours are wetter than this pixel, stored pigment darkens, so the outside of a wet blob collects paint. Spread still owns the neighbour mix.
FORBID: speed-thinning that shrinks the flick (the flick is the splatter), a drip solver, an IQ palette, moving the mouse stash.
A PACKING: `paint.rgb + wetness.a`, `(0,0)` mouse stash kept.
FORMULA: wet-edge accumulation (§12.2C), boundary form (neighbour wetness above this pixel). Only this file.
