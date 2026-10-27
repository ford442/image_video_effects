# Idea Cards — cursor/batch-11 liquid, ripple, vortex (2026-10-26)

Written before WGSL edits. Twelve shaders, 121–153 lines. Each card adds **two** new ideas. Earlier ideas stay. Saved `params` stay byte-exact. No shared spring, ripple stamp, or IQ palette.

Formula cap: each §12.2 row on at most two files.

- Isotropic 9-point: `viscous-drag-bilateral`, `raindrop-ripples`
- Deep-water dispersion: `liquid-perspective`, `rgb-ripple-waves`
- MacCormack: `liquid-viscous-grokcf1` only
- Cauchy: `rgb-ripple-waves` only
- Speed-thinning: `velvet-vortex` only
- Dropout tail and chroma delay: `liquid-glitch` only
- Beer–Lambert and Henyey–Greenstein: `sim-volumetric-fake` only
- Vorticity confinement: `liquid-viscous-simple` only
- Surface tension: `liquid-mirror` only
- No §12.2 row: `interactive-ripple`, `vortex-drag`

`viscous-drag-bilateral`, `interactive-ripple`, `rgb-ripple-waves`, `velvet-vortex`, `vortex-drag`, `sim-volumetric-fake`, and `raindrop-ripples` still paste the 13 bindings. Those headers are migrated to `#include "_prelude.wgsl"` as infrastructure, not the upgrade.

---

## viscous-drag-bilateral

IDENTITY: a viscous gel stores a displacement, drags it with the pointer and click fronts, then reconstructs the photo with a color-range bilateral.

KEEP VERBATIM: 5×5 bilateral spatial×range weights; range sigma and hue and drag params; radial plus tangential pointer drag; click-front injection; spectral phase from the displacement angle; A = displacement.xy, edge confidence, coating. No extraBuffer.

MECHANISM INTERROGATION:
- tactic 1: neighbor mixing is a 4-point box. The same diffusion wants an isotropic stencil.
- tactic 2: a gel holds still on a color edge instead of creeping across it.
- tactic 3: edge confidence is written and never fed back into the mix.
- tactic 6: C.z is last frame's edge confidence. C.xy is the displacement the mix already reads.

ADD:
  1. Isotropic 9-point diffusion (§12.2D) — same viscosity mix, corners included so the gel does not prefer the axes.
  2. Edge-confidence stall — previous C.z reduces that mix, so a pixel the bilateral already called an edge keeps its own displacement.

FORBID: a spring, a new palette, replacing the bilateral with a blur.
A PACKING: raw — displacement.xy, edge confidence, coating thickness. ACES on display only.

---

## liquid-viscous-grokcf1

IDENTITY: a viscous nebula — FBM warp, helical conveyor, pointer vortex, ripple shear, filament veins, and a history trail.

KEEP VERBATIM: fbm warp and helical flow; spring in extraBuffer[133..138]; drag core and ripple tangent; vein and nebula hue; trail mix from history.a; params viscosity / turbulence / nebula glow / spectral shift.

MECHANISM INTERROGATION:
- tactic 1: the trail samples history once along the displacement. Advection of that color can be corrected with a back-step.
- tactic 2: an ionization front is a thin edge of the density the warp already builds, not a new gas.
- tactic 3: `warpA * 0.55 + warpB * 0.55` is smoothed into density and then thrown away.
- tactic 6: C is display color. The trail mix stays. No new field.

ADD:
  1. MacCormack trail (§12.2D) — forward history plus half the error against the backward sample, clamped to those two colors, then the existing trail mix.
  2. Ionization front — a thin rim where that pre-smoothstep density crosses 0.55, tinted with the existing nebula hue and scaled by nebula glow.

FORBID: a new palette, a second spring, Gray-Scott.
A PACKING: ACES display RGBA (unchanged).

---

## liquid-perspective

IDENTITY: a perspective-compressed Gerstner sheet with a Jacobian parallax, Snell/Fresnel refraction, and biolume on depth edges.

KEEP VERBATIM: three Gerstner directions; perspectiveTilt on frequency; Jacobian in the parallax denominator; pointer pull; click rings; chromatic split from color shift; fresnel and biolume; params speed / density / intensity / color shift.

MECHANISM INTERROGATION:
- tactic 2: longer water waves outrun shorter ones. The sheet already has three wavenumbers and one clock.
- tactic 3: `jacobian` is only a parallax divisor. Steep slopes are where a real sheet breaks into foam.
- tactic 6: C is display history. The feedback mix stays.

ADD:
  1. Deep-water dispersion (§12.2D) — phase speed scales as sqrt(kMid / k), mixed onto the existing per-wave factor so the middle wave keeps its clock. Speed still scales all of them.
  2. Jacobian foam — pale caps where the slope vector the loop already accumulates is steep. Intensity still owns amplitude, which owns that slope.

FORBID: a spring, a new wave direction, replacing Snell.
A PACKING: ACES display RGBA (unchanged).

---

## interactive-ripple

IDENTITY: a pointer packet plus click ripples whose speed follows depth, with crest chroma, caustics, bloom, and a lattice background.

KEEP VERBATIM: wave height / count / speed / damping; depth-scaled speed; pointer packet; crest chroma; causticPattern, bloom, film, SSS; A = offset.xy, ripple height, alpha. No spring.

MECHANISM INTERROGATION:
- tactic 2: a click is a ring that arrives, not a disc that oscillates everywhere at once.
- tactic 3: the signed wave is reduced to abs() for height. Troughs are where a ripple focuses light.
- tactic 6: C is not read. Do not start a height solver. A stays the analytic offset and height.

ADD:
  1. Traveling ring window — the existing click envelope keeps a quiet disc and a brighter ring at age × wave speed. Damping still decays it.
  2. Trough focus — the existing caustic brightens where the signed wave is negative.

FORBID: a spring, a height-field solver, an IQ palette (the film cosine stays as it is).
A PACKING: raw in A (offset.xy, ripple height, alpha). ACES on display only.

---

## rgb-ripple-waves

IDENTITY: radial RGB waves from the pointer, each channel phase-shifted, with Beer–Lambert alpha by wavelength.

KEEP VERBATIM: frequency / speed / amplitude / channel phase; mouse-centered radial sine; per-channel displacement; Beer–Lambert `calculateChannelAlpha` at 650/550/450 nm; crest light from the green wave. No click-ripple system.

MECHANISM INTERROGATION:
- tactic 2: long wavelengths outrun short ones, and glass dispersion is 1/λ², not a linear 0,1,2 step.
- tactic 3: the three sines share one `time * speed`. The phase slider is a constant offset.
- tactic 6: C is not read. A stays display color.

ADD:
  1. Deep-water speed (§12.2D) — each channel's time term scales by sqrt(λ / 550 nm). Green keeps the slider speed.
  2. Cauchy phase (§12.2F) — the channel-phase slider is B in n(λ) = 1 + B/λ², red anchored, blue pulled farther than a linear step.

FORBID: click shockwaves, a spring, replacing Beer–Lambert.
A PACKING: ACES display RGBA.

---

## velvet-vortex

IDENTITY: a soft velvet swirl around a spring-followed pointer, with arm count from mids, per-arm spectrum, and click-ring twist.

KEEP VERBATIM: radius / strength / softness / pulse; spring integration (single writer at (0,0)); arm count; per-arm plasma bin; ripple_twist; velvet tint and shock sheen.

MECHANISM INTERROGATION:
- tactic 2: velvet pile has a nap. Light across the fibers sheens; light along them goes dull.
- tactic 3: spring velocity is integrated and only moves the center. It never changes the swirl's width.
- tactic 6: C is not read. Do not add a trail field.

ADD:
  1. Nap sheen — fiber direction is the swirl tangent. Across-fiber light brightens; along-fiber light darkens. Softness still owns the falloff.
  2. Speed-thinned radius (§12.2C) — the existing spring speed narrows the radius. Pulse still multiplies it.

FORBID: a new palette, a second ripple system, per-arm color from plasmaBuffer[1..] beyond the phase the file already uses.
A PACKING: ACES display RGBA.

---

## vortex-drag

IDENTITY: a sprung vortex that twists and pinches the photo, with a helical streak, a ribbon, and click rings.

KEEP VERBATIM: twist / radius / pinch / hardness; spring in extraBuffer[133..138]; helix and ribbon; click rings; palette on the ribbon only; history mix inside the disc.

MECHANISM INTERROGATION:
- tactic 2: pinching a vortex spins it up; bulging it slows it. The pinch currently only scales radius.
- tactic 3: `ribbon` is a bright thread. The photo under a real ribbon is stretched thin.
- tactic 6: C is display history. The 0.16 mix stays.

ADD:
  1. Pinch spin-up — positive pinch multiplies the twist; bulge reduces it. The pinch still scales the rotated vector.
  2. Ribbon groove — the photo under the existing ribbon darkens before the palette thread is added.

FORBID: a new spring, a second palette, vorticity on a field this shader does not store.
A PACKING: ACES display RGBA (unchanged).

---

## liquid-glitch

IDENTITY: block-quantized liquid tears, bad-row slip, a pointer wake, click shard bursts, chromatic split, and a scanline.

KEEP VERBATIM: block size from the block-scale param; row hash tear; fluid stream; spring in extraBuffer[133..138]; shard bursts; scanline; history persistence; params block scale / corruption / burst / chromatic shift.

MECHANISM INTERROGATION:
- tactic 2: a dropout is a streak with a tail along the scanline, not a uniform row shift. Chroma on a scanline lags luma.
- tactic 3: `isBadSignal` shifts the whole row by one amount. `split` is a symmetric ±x.
- tactic 6: C.a is the trail weight. Do not store a latch in it.

ADD:
  1. Dropout tail (§12.2B) — the bad-row offset and a light streak fade along x.
  2. Chroma delay line (§12.2B) — green stays on the smear; red and blue sample behind it. The chromatic-shift slider still sets the distance.

FORBID: a Schmitt latch in alpha, thin-film, a new block shape.
A PACKING: ACES display RGBA (unchanged).

---

## sim-volumetric-fake

IDENTITY: fake god rays — a radial march toward a moving light, with depth occlusion, dust, and motes.

KEEP VERBATIM: light intensity / dust / scattering / noise speed; moving lightPos; occlusion against lightDepth; mote hash on the taps; dust noise; the 32-tap cap. No pointer.

MECHANISM INTERROGATION:
- tactic 2: a shaft is absorbed as it travels, and scatter prefers the forward lobe.
- tactic 3: attenuation is only (1−t)² times occlusion. The closing `alignment²` is a phase function with no width control.
- tactic 6: C is not read. A stays display color.

ADD:
  1. Beer–Lambert along the march (§12.2F) — extinction from scattering and dust multiplies the existing attenuation.
  2. Henyey–Greenstein (§12.2F) — the same view/light angle, lobe width from scattering, peak brightness matched to the old alignment term.

FORBID: click ripples, a spring, mouse-aimed light.
A PACKING: ACES display RGBA (unchanged).

---

## liquid-viscous-simple

IDENTITY: a laminar flow plus convective shear, a pointer vortex, spiral ripples, 4-tap cohesion, and shear-thinning.

KEEP VERBATIM: `flowField`; convective shear; pointer tangent drag; spiral ripple term; shear-thinning of viscosity; fresnel sheen; chromatic split from color shift; params viscosity / turbulence / ripple strength / color shift. No spring.

MECHANISM INTERROGATION:
- tactic 1: `flowField` is a velocity with a curl the shader never uses.
- tactic 2: high shear should slip the photo along the flow, not only lower a scalar viscosity.
- tactic 3: `shearRate` only divides viscosity.
- tactic 6: C is display history. The feedback mix stays.

ADD:
  1. Vorticity confinement (§12.2D) — analytic curl of `flowField`, a small cross-product swirl. Turbulence still scales the field.
  2. Shear streak — where shear is high, mix in a sample taken along `ambientFlow`.

FORBID: a spring, replacing flowField with noise, a 9-point stencil (that row is used on the gel and the pond).
A PACKING: ACES display RGBA (unchanged).

---

## liquid-mirror

IDENTITY: a height/velocity pond used as a mirror, with pointer push, click rings, fresnel, glitter, and energy-roughened reflection.

KEEP VERBATIM: 5-point wave step; rest spring; damping and tension from smoothness; glitter path; 4-tap rough reflection; fresnel and specular; params distortion / smoothness / reflectivity / push size; A = height, velocity, energy, coverage.

MECHANISM INTERROGATION:
- tactic 2: surface tension rounds sharp peaks. A finger in water piles a ring at the contact edge, not only a dent in the middle.
- tactic 3: the laplacian is applied raw. Dividing by the slope is curvature. `pointerMask * (1 − pointerMask)` is the lip and is not used.
- tactic 6: C.r/g/b/a stay height, velocity, energy, coverage. Do not move the glitter or the rough blur.

ADD:
  1. Surface tension (§12.2D) — velocity loses a curvature term `laplacian / |slope|`, scaled down by smoothness. The rest spring and the laplacian tension stay.
  2. Push meniscus — the radial lip of the existing push mask adds a ring of impulse.

FORBID: a new spring, repacking A, removing glitter or the energy blur.
A PACKING: raw — R=height, G=velocity, B=surface energy, A=coverage. ACES on display only.

---

## raindrop-ripples

IDENTITY: a rain-driven pond. Wave speed is c² of the height solver, a pointer shield calms the interior, and slope refracts the photo with a caustic in converging troughs.

KEEP VERBATIM: rain hash; decay; waveC from the speed slider; shield radius and rim bump; slope refraction; specular; caustic from negative laplacian; A.rg = height, previous height.

MECHANISM INTERROGATION:
- tactic 1: the wave step uses a 5-point Laplacian. The same c² wants an isotropic stencil.
- tactic 2: steep rings damp faster than a broad swell. Decay is currently uniform.
- tactic 3: `lap` is the wave drive and the caustic, and it is not a damping weight.
- tactic 6: C.rg is the solver state. Do not store display color in A.

ADD:
  1. Isotropic 9-point Laplacian (§12.2D) — corner taps included, scaled so a flat field and a single-pixel spike match the 5-point magnitude. waveC is unchanged.
  2. Steep-slope damping — a fraction of decay is spent where `|lap|` is large. The decay slider remains the base.

FORBID: a spring, deep-water phase speed (that row is on the Gerstner sheet and the RGB waves), repacking A.
A PACKING: raw height / previous height in A.rg (A.b still the laplacian). ACES on display only.
