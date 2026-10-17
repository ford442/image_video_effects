# Cursor batch-02 — Idea Cards

Written before WGSL edits. 2026-10-17.

```
SHADER: quantum-foam-pass2
IDENTITY: chromatic particle advection through the foam field pass 1 just wrote
KEEP VERBATIM: curl advection, quaternion tint, RGB dispersion, anisotropic mix, spectralPower, B = color + emission
ADD:
  1. Curl comet — a short upstream sample along curl+warp so each tracer has a head and a tail
  2. Film scintillation — cell-boundary emission breathes, so pass 3's glow twinkles on the films
FORBID: a new solver, IQ palette, click shockwaves
A PACKING: dataB and dataA = finalColor.rgb + emission (pass 3 reads B via the graph copy)
```

```
SHADER: quantum-foam-pass3
IDENTITY: glow, haze, vignette, and ACES grade of the particle buffer
KEEP VERBATIM: 3x3 glow, purple depth haze, vignette, saturation/contrast grade, ACES, gamma, early-out passthrough
ADD:
  1. Flow-smear glow — the kernel shifts along the emission gradient (flow speed)
  2. Beer thickness veil — transmitted color darkens where the glow is dense (diffusion)
FORBID: writing A (pass 2 owns the particle pack), springs
A PACKING: pass 3 writes color only; C is read as pass 2's (rgb, emission)
```

```
SHADER: liquid-pass1
IDENTITY: capillary + gravity wave solver with click packets and a meniscus
KEEP VERBATIM: laplacian/biharmonic split, click packets, ambient waves, meniscus, A = (h_prev, h_curr, velocity, age)
ADD:
  1. Crest lean — height advects down its own slope so fronts steepen
  2. Capillary fringe — Color Shift (unread on this pass) adds a faster short wave ahead of the swell
FORBID: replacing the wave equation, ACES on the stored heights
A PACKING: raw (h_prev, h_curr, velocity, age); pass 2 reads C.g as height
```

```
SHADER: liquid-pass2
IDENTITY: refracted photo under a Fresnel / Beer-Lambert water surface
KEEP VERBATIM: normal from height, Schlick Fresnel, per-channel absorption, turbidity = Color Shift, no A write
ADD:
  1. Fold caustics — bright filaments where the height laplacian focuses
  2. Wetting rim — a dark contact line where the surface meets the depth edge
FORBID: writing A (that would erase the height field), a new fluid solver
A PACKING: display ACES RGBA on writeTexture; height stays in pass 1's A
```

```
SHADER: vortex-pass1
IDENTITY: four analytic vortices, Biot-Savart speed, confinement, turbulent fbm
KEEP VERBATIM: four cores, tangent+inflow velocity, confinement, fbm turbulence, A = (vx, vy, vorticity, velMag)
ADD:
  1. Pairing jet — the counter-rotating pair (cores 0 and 1) swims perpendicular to the line of centers
  2. Viscous memory — blend toward last frame's velocity when C.a looks like velMag, not a color alpha
FORBID: image-as-velocity, overwriting A with display color
A PACKING: raw (vx, vy, vorticity, velMag+2). The +2 keeps the field distinct from a color alpha. Pass 2 must not clobber A.
```

```
SHADER: vortex-pass2
IDENTITY: chromatic trail and iridescent curl tint of a swirling picture
KEEP VERBATIM: per-channel trail blur, hsv curl tint, palette grading, swirl/iridescence/trail/palette sliders
ADD:
  1. Sim-field warp — when C is pass 1's velocity, advect along that field and darken a Rankine eye
  2. Eyewall braids — Kelvin-Helmholtz ripples on the speed ring around the eye
FORBID: writing display color into A (that erases pass 1's velocity), a second vortex solver
A PACKING: pass 1 owns A. Pass 2 reads C as velocity when C.a > 1.5, else the photo-as-flow fallback.
```

```
SHADER: chromatographic-fluid
IDENTITY: RGB dyes with different viscosity in one wind, hold-paint and click solvent
KEEP VERBATIM: seven-node graph, A/C = dye.rgb + temperature, per-channel Jacobi viscosity, shared wind, phase change, hold paint, click splash
ADD:
  1. Differential migration — in advect, red takes a shorter step than blue so the dyes pull apart along the wind
  2. Solvent front — in render, a pale band where dye is present and the downwind neighbor is empty
FORBID: a new palette, packing temperature into a color channel, springs
A PACKING: raw dye.rgb + temperature in A at every node; ACES only on the render color
```

```
SHADER: sim-fluid-feedback-field
IDENTITY: one running pass of curl-driven velocity with a mouse push (pass 2 and pass 3 are not dispatched)
KEEP VERBATIM: curl seed, viscosity damping, radial mouse impulse, slider roles (x viscosity, y turbulence, z mouse force)
ADD:
  1. Self-advection — semi-Lagrangian step of the velocity stored in C, mixed back with the curl seed
  2. Dye streak — a scalar dye rides that velocity, warps the photo, and brightens with Glow
FORBID: pretending the unwired pass 2/3 run, ACES on the stored velocity
A PACKING: raw (velX, velY, dye, 1). Display ACES is writeTexture only.
```

```
SHADER: gen-spectral-ferrofluid
IDENTITY: four-pole ferrofluid with flux spirals, Cotton-Mouton tint, meniscus mounds, crowns, Barkhausen flicker
KEEP VERBATIM: dipole field, temporal field memory, all five existing ideas, A = (fMag*0.25, fieldDir, alpha)
ADD:
  1. Magnetic-mirror beads — discrete bright beads on the inner shoulder of each pole, inside the Rosensweig crown
  2. Bloch domain wall — a dark seam where this frame's field direction disagrees with the stored one
FORBID: a new creature, rewriting the dipole, changing A packing
A PACKING: raw field state (fMag*0.25, fieldDir.x, fieldDir.y, alpha)
```

```
SHADER: gen-aethereal-ferrofluid-chrono-core
IDENTITY: raymarched ferrofluid sphere, Voronoi needles, 12-tick clock ring, seam bioluminescence
KEEP VERBATIM: sphere + needle displacement, clock ticks, seam glow, held-pointer dipole, display A packing
ADD:
  1. Tip bulbs — the sharpened needles end in a small droplet instead of a point
  2. Equatorial current sheet — a thin latitude glow between the clock ticks, not on them
FORBID: a second organism, retiming the 12-tick ring, springs
A PACKING: ACES display RGBA; C unread
```
