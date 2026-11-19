# Idea Cards — Grok (generative field ten, 2026-11-19)

Written before the WGSL edits. Ten shaders the user listed by size. Each card adds **two or three** ideas in the existing main path. Saved `params` stay byte-exact. No shared spring, ripple stamp, or new IQ palette.

These files already carry an earlier idea pass (photon rings, return stroke, agate, Feigenbaum-adjacent windows, watersheds, dust lanes, FTLE ridges, Morse index, Rayleigh modes, lub-dub). This pass deepens the same mechanism. It does not replace it.

Formula rule: a §12.2 row is newly applied on at most one file here.

- Cauchy (§12.2F) is the wormhole's Einstein ring only.
- Fresnel–Schlick (§12.2F) is the metaball metal only.
- March-step occlusion (the step count the geode march already throws away; not the 5-tap §12.2E formula) is the geode only.

`gen-topology-flow` and `lorenz-attractor-flow` still paste the binding header. Migrating them to `#include "_prelude.wgsl"` is infrastructure. It is not an idea and does not by itself bump `Upgraded:`. The idea edits do.

```
SHADER: gen-plasma-psychedelic-wormhole
IDENTITY: a plasma tunnel rushing into a throat, with spiral arms, photon-sphere subrings, click-spawned lenses, frame-drag, and wall billows.
KEEP VERBATIM: 1/r tunnel coordinates; 5-octave swirl; radial bands; spiral arms; photon subrings shrinking by e^-π; point-mass deflection α=θE²/b; frame-drag shear; Kelvin–Helmholtz billows; blackbody palettes; inverse-ACES trail in A. Params Brightness / Travel Speed / Tunnel Scale / Color Shift.
MECHANISM INTERROGATION:
  tactic 2: a point-mass lens is chromatic; the throat inside the photon sphere is a plunge, not an orbit
  tactic 3: θE is one scalar reused for deflection and for a single white ring
  tactic 6: A stays ACES display; the trail still recovers HDR through acesInverse
ADD:
  1. Chromatic Einstein ring — R/G/B critical radii around the existing θE (§12.2F Cauchy). Deflection stays the green radius
  2. Throat plunge curtain — inside the photon sphere the streaks are radial infall, not another spiral arm
FORBID: a new spring, a second tunnel motif, gravitational redshift (the accretion disk already owns that)
A PACKING: ACES display RGBA in A (unchanged; feedback recovers HDR via acesInverse)
```

```
SHADER: gen-lichtenberg-storm
IDENTITY: branching Lichtenberg dendrites from a spring electrode, with a return-stroke head, etched channels, a corona sheath, and a click shock ring.
KEEP VERBATIM: licht() dendrite; return-stroke head and behind-mask; corona from an 8-tap load of C.g; etch = C.g; spring in extraBuffer[133..138]; shock ring; OkLab + blackbody grade. Params Branch Jitter / Glow Intensity / Storm Frequency / Afterglow Persistence.
MECHANISM INTERROGATION:
  tactic 2: a stepped leader is a chain of bright steps with dark gaps, and a cooling channel beads
  tactic 3: the front radius is computed and then only used as a smooth mask
  tactic 6: C.g is etched charge. Beads belong on charge that is no longer the live stroke
ADD:
  1. Stepped-leader gaps — behind the existing head the channel breaks into bright steps and dark gaps
  2. Bead lightning — hot knots on cooling etched charge, absent where the live stroke is bright
FORBID: a second corona, a new electrode spring, IQ palette
A PACKING: raw sim state (A = energy, etched charge, shock ring, 1). ACES on writeTexture only
```

```
SHADER: gen-galactic-aether-crystal-geode-core
IDENTITY: a raymarched cracked geode — agate shell, KIFS crystals, plasma core, druse, and a convecting hollow.
KEEP VERBATIM: map() materials 1/2/3; KIFS; agate bands from the crack cells; amethyst zoning; druse; gas swirl; params Crystal Density / Core Glow / Fractal Iterations / Gas Density.
MECHANISM INTERROGATION:
  tactic 2: a real geode has an ochre weathering rind outside the agate, and bubbles trapped in the crystals
  tactic 3: the march step count is discarded; grazing cracks take many more steps than a facing wall
  tactic 6: A stays ACES display. No new field
ADD:
  1. Weathering rind — ochre crust on the outer shell, outside the agate bands
  2. Fluid inclusions — hash beads inside crystal material, cell frequency from Crystal Density
  3. March-step occlusion — hits that took more steps (crevices) darken. The step count is the one the loop already has
FORBID: a new SDF primitive, thin-film on the shell (the metaball owns the film this batch), a 5-tap map() AO (map is already the cost)
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: gen-bifurcation-diagram
IDENTITY: the logistic-map bifurcation diagram — density bins, Lyapunov tint, period-3 window, superstable points, cobweb ticks under the pointer.
KEEP VERBATIM: one logistic loop for density, transient ghost, and Lyapunov; four palettes mixed by Color Scheme; period-3 marker; superstable x=0.5; cobweb ticks; pointer spring lens; scan and click fronts already in the file. Params R Parameter Position / Zoom Level / Iteration Count / Color Scheme.
MECHANISM INTERROGATION:
  tactic 2: the cascade has named r landmarks, and the r→4 measure diverges at the endpoints
  tactic 3: the pointer column already evaluates the logistic map for ticks and never marks the fixed point x=1−1/r
  tactic 6: A stays HDR density. No new packing
ADD:
  1. Feigenbaum hairlines — r = 3, 3.44949, 3.54409, 3.56441 and the accumulation 3.56995, only when that r is inside the zoom window
  2. Invariant-density cusps — for r near 4, existing density brightens toward x=0 and x=1 as 1/sqrt(x(1−x))
  3. Cobweb fixed-point tick — x=1−1/r in the pointer column, the parabola–diagonal intersection next to the existing ticks
FORBID: a new map, a second spring, replacing the density bin
A PACKING: HDR density RGB + alpha (unchanged). ACES on writeTexture only
```

```
SHADER: gen-thermal-rainbow-topography
IDENTITY: a thermal-rainbow height field with contours, a fault shear, a caldera, watershed channels, and saddle eddies.
KEEP VERBATIM: terrainHeight; diffusion from C.a; contours; fault; caldera; channel from −laplacian; saddle eddy; curl flow; Worley cells. Params Intensity / Evolution Speed / Terrain Scale / Color Shift.
MECHANISM INTERROGATION:
  tactic 1: slope is stored as a length. The same finite difference is a direction
  tactic 2: a summit (low slope, convex) vents; a saddle (low slope, flat laplacian) does not
  tactic 3: (hR−hL, hU−hD) is reduced to a length and the direction is discarded
ADD:
  1. Slope-aspect sun — the existing height gradient dotted with a slow azimuth. Evolution Speed turns the sun
  2. Fumarole vents — white plumes where slope is low and the laplacian is convex, the complement of the saddle eddy
FORBID: another caldera, a new fault, a spring
A PACKING: A.rgb = ACES display history, A.a = diffused height (unchanged)
```

```
SHADER: gen-astral-plasma-accretion-forge
IDENTITY: a Keplerian accretion disk around a horizon, with dust lanes, gravitational redshift, Rossby knots, and polar reconnection.
KEEP VERBATIM: torus map; two-phase Keplerian shear; dust lanes and sublimation radius; redshift g; Rossby knots; polar reconnection; horizon occultation. Params Core Density / Accretion Spin / Flux Intensity / Core Temp.
MECHANISM INTERROGATION:
  tactic 2: orbital motion Doppler-beams the approaching limb; the shadow is ringed by the photon orbit
  tactic 3: impact parameter length(cross(ro, rd)) is already the bloom denominator and is not a ring
  tactic 6: A stays ACES display
ADD:
  1. Orbital Doppler beaming — line-of-sight φ velocity of the existing Keplerian frame, disk only, so one limb is hot
  2. Schwarzschild photon ring — a thin ring at b = 2.598 × the existing horizon radius, using the impact parameter the bloom already computes
FORBID: a second dust model, Cauchy (the wormhole owns it), replacing the torus
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: lorenz-attractor-flow  (catalog id gen-lorenz-attractor-flow)
IDENTITY: a Lorenz flow field plus a swept 3D orbit tube, FTLE ridges, wing-switch bands, and flow-advected feedback.
KEEP VERBATIM: Euler step; σ=10, ρ=28, β=8/3; shadow-twin FTLE; hop parity; upstream C sample; SDF tube; orbit-trap kaleidoscope. Params Integration Speed / Color Shift / Glow Intensity / Mouse Influence.
MECHANISM INTERROGATION:
  tactic 2: the picture of this attractor is the section where z crosses ρ−1, and the two nonzero equilibria the wings circle
  tactic 3: the tube loop already has tp.z and never tests the section plane
  tactic 6: A stays ACES display. The bass smoother stays at extraBuffer[133]
ADD:
  1. Poincaré knots — a bright knot on the tube where z crosses 27 (ρ−1)
  2. Equilibrium eyes — soft markers at the nonzero fixed points (±√(β(ρ−1)), same, ρ−1) in the tube frame
FORBID: a new ODE, another kaleidoscope fold, a spring
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: gen-topology-flow
IDENTITY: a Morse height field with gradient-flow lines, critical points from the Hessian, and separatrix whiskers.
KEEP VERBATIM: heightField; particle advection; Morse index from det and trace; separatrix whiskers; relief light; valley haze. Params Flow Speed / Height Complexity / Particle Density / Trail Persistence.
MECHANISM INTERROGATION:
  tactic 1: det is a yes/no. Persistence is how large that det is
  tactic 2: sources and sinks are opposite signs of the same trace the index already uses
  tactic 3: the contour test is global. The contour that passes through a saddle is the critical level set
ADD:
  1. Persistence — critical glow and whiskers scale with |det H|, so shallow noise stays dim
  2. Source/sink tint — divergent flow (trace < 0) runs warm, convergent flow runs cold, on the existing flow colour
  3. Critical level set — the height contour through a saddle lights, the figure-eight next to the whisker
FORBID: a second particle loop (the existing one is already the cost), a spring, a new height function
A PACKING: linear/HDR history in A; ACES on writeTexture only (unchanged)
```

```
SHADER: gen-metaball-soft-body
IDENTITY: a metallic metaball liquid with Rayleigh shape modes, a beaded neck, a soap-film meniscus, and a nephroid caustic.
KEEP VERBATIM: fieldRaw modes l=2 and l=3; neckBeading at λ≈9.02 r; meniscus film; nephroid crescent; mouse gravity. Params Ball Count / Surface Roughness / Metal Hue / Caustic Strength.
MECHANISM INTERROGATION:
  tactic 2: past the Plateau threshold a bead pinches off; a metal's reflectance is Schlick in its own F0; a tight neck is high pressure
  tactic 3: Metal Hue is a diffuse tint. The Fresnel term ignores it. |∇f| is used for the caustic and not for pressure
ADD:
  1. Satellite droplet — a small ball at the bridge midpoint once stretch exceeds the beading threshold, added to the same field the gradient taps
  2. Fresnel–Schlick conductor — F0 is Metal Hue (§12.2F). Grazing goes white
  3. Young–Laplace darkening — large |∇f| (tight curvature) darkens the surface. Roughness still scales it
FORBID: a new solver, a second film, a spring
A PACKING: ACES display RGBA in A (unchanged)
```

```
SHADER: gen-sentient-liquid-neon-fractal-heart
IDENTITY: a pulsing fractal heart with lub-dub, a systolic pressure wave, an oxygenation gradient, Purkinje flashes, and a diastolic refill.
KEEP VERBATIM: map() fractal heart; lub-dub timings; systolic wavefront; oxygenation by radius; Purkinje branch; diastolic refill; artery material. Params Fractal Complexity / Pulse Intensity / Neon Saturation / Bioluminescent Fog.
MECHANISM INTERROGATION:
  tactic 2: the heart sits in a pericardial sac, the valve snaps at S1/S2, and the muscle is briefly refractory after the beat
  tactic 3: S1 age is computed for the traveling wave and is never a closure flash. The march distance passes 0.055 and is not a membrane
  tactic 6: A stays bounded HDR history. The sac is not a new material id
ADD:
  1. Pericardial sac — a thin shell one step outside the existing myocardium. A step that jumps the band still counts as a crossing. It breathes because distance is already in the pulsed metric
  2. Valve-closure flash — a white snap at the onset of S1 and a weaker snap at S2, separate from the traveling pressure wave
  3. Refractory dip — a short desaturation just after S1, before the diastolic refill begins
FORBID: a new heart SDF, Schlick (the metaball owns it), an ECG overlay
A PACKING: raw HDR display history (bounded 0..5) in A.rgb, coverage in A.a; ACES on writeTexture only (unchanged)
```
