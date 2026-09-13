SHADER: gen-hyper-refractive-rain-matrix
IDENTITY: an orbiting camera raymarching a falling lattice of viscous, smooth-min-merged capsule rain drops that refract a cosine/blackbody sky, with Fresnel rims, surface caustics, pointer repulsion and click caustic rings over HDR temporal trails.
KEEP VERBATIM: map() capsule lattice + 3x3 smin neighbour merge; rainDensity/dropSpeed/fluidViscosity/stormIntensity roles on zoom_params.xyzw; pointer repulsion in world XZ; 100-step march; cosinePalette+blackbody OkLab sky; Fresnel rim + caustics; click caustic rings from u.ripples; raw HDR A/C history; ACES on display only.
EXISTING IDEAS: viscous drop merging (smin), pointer repulsion, treble caustics, click caustic rings, temporal HDR trails.
ADD:
  1. Storm lightning flashes — hash-gated, time-bucketed double-strobe (bass-triggered, rate/brightness scaled by Storm Intensity) that floods the sky with ~11000K blackbody light and back-lights the drops' Fresnel rims; native because the description already promises "storm flashes" and Storm Intensity is the storm, yet no flash exists.
  2. Spectral dispersion in the drops — refract R/G/B with separate eta (spread by Fluid Viscosity and mids) and sample the refraction palette per channel, so drop rims split into prismatic fringes; native because the whole effect is "hyper-refractive" and the refraction step is already there.
  3. Fall-aligned streak history — the C history is read (exact textureLoad) from pixels displaced up along the fall direction by an amount set by Drop Speed, so trails smear into vertical rain streaks instead of static ghosting; native because the rain falls in -Y and the temporal trail is existing machinery.
FORBID: spring cursor in extraBuffer, new ripple shockwave system, replacing capsules with other primitives, IQ palette as a new overlay, conveyors, changing param roles.
A PACKING: raw HDR refractive rain RGB + semantic coverage alpha (unchanged; C read as raw HDR via exact textureLoad; ACES on writeTexture only).

## Notes
- Kept verbatim: map() capsule lattice + 3x3 smin merge, pointer repulsion, 100-step march, calcNormal, cosine/blackbody OkLab sky, Fresnel rim, caustics, fog, click caustic rings, temporal blend weights, ACES on display, depth write, all four param roles. JSON `params` byte-exact.
- A packing: raw HDR RGB + coverage alpha, unchanged; C read raw via exact textureLoad (now two taps); no textureStore to C; no extraBuffer use.
- Idea 1 (lightning): `lightningFlash()` line 89; sky flood line 187; rim back-light line 226. Driven by Storm Intensity (rate, chance, brightness) and bass (trigger chance).
- Idea 2 (dispersion): line 203 — R/B refract at eta -/+ disp (disp from Fluid Viscosity + mids), per-channel palette weighted by rim angle.
- Idea 3 (streaks): line 270 — history pulled from pixel.y + streakLen (1..10 px by Drop Speed, + bass), mixed 0.7 with in-place history.
- Floor fixes: Fresnel `pow(1+dot(rd,n),4)` base clamped to [0,1] (negative base -> NaN); header rewritten to §8 banner; JSON features + "mouse-driven" (pointer repels drops), "upgraded-rgba"; description now honest (previous "storm flashes" did not exist in code).
- Gates: naga "Validation successful"; wgsl_precommit_gate 1/1 pass, 0 extraBuffer violations. No real-GPU visual QA.
