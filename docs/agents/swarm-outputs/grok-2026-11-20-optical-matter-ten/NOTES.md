# Notes — optical / matter ten (2026-11-20)

Idea Cards were written first in `BRIEFS.md`. Saved `params` were not renamed or re-defaulted. ACES is on the display path. Where A is a raw field, that write was left raw.

Formulae, each new on one file: vorticity confinement (§12.2D) on `glass-wipes-coupled`; soft inverse-square (§12.2F) on `photonic-caustics`; cos⁴ vignetting (§12.2A) on `virtual-lens`. No other §12.2 row is new. Coefficient of finesse on `spec-iridescence-engine` sharpens the two-beam sum already in that file. It is not the Airy-disc row. No shared spring, shockwave, or palette was added. Springs and click paths that were already in a file were left in place.

Nine shaders had a pasted binding header. They now `#include "_prelude.wgsl"`. That migration is not the upgrade.

`spec-iridescence-engine` and `glass-wipes-coupled` gained `"upgraded-rgba"` in features. Both already tone-map the display, and the Idea Card is in the WGSL. No param was edited.

## mouse-polarized-light-field

- Kept: Polarization Angle, Birefringence, Fringe Density, Color Shift, the pointer angle, per-channel analyzer, hue shift, moiré, chromatic fringe spacing, treble shimmer, click vortices, analyzer flash.
- Added: Malus extinction — the cos² term that was computed and discarded now darkens the field, with a leak; specimen optical path — luma scales the existing retardation so isochromes follow the photo.
- A packing: ACES display RGBA. C is unread. The display path gained ACES; A matches it.

## spec-iridescence-engine

- Kept: Film Thickness, Film IOR, Intensity, Turbulence, the spring in `extraBuffer[133..138]`, the 380–700 nm loop, thickness from depth, noise, the lens, the held pointer, and click rings, the Fresnel cover, the 8% C trail.
- Added: coefficient of finesse — the cosine stays and blends toward a peak-normalized Airy shape as Film IOR rises; transmitted photo — bright bands remove the photo, dark bands leave it. Cover is still the Fresnel weight.
- A packing: ACES display RGBA. C is that color trail.

## gen-turing-morphogenesis

- Kept: Feed Rate, Evolution Speed, Pattern Scale, Color Shift, the three regimes, activator–inhibitor, coat grain, inhibitor halo, chemical-front ridge, domain patches, mouse deposit, the organic ramp, C color persistence.
- Added: chemical boundary — the activator gradient already used for grain tightens the soft threshold where it is steep; stain aging — last frame's luma walks Color Shift along the same ramp.
- A packing: ACES display RGBA.

## aero-chromatics-prismatic

- Kept: Wind Force, Smoke Decay, Chromatic Split, Source Intensity, base wind, mouse wind, the curl field, per-channel history offsets and decay, the Cauchy prism loop, the Schlieren sample.
- Added: Kármán street — the curl is gated to the downstream wake and flips sense across the centerline; Bernoulli thinning — high `speedMag` mixes the trail back toward the photo.
- A packing: ACES display RGBA. C is that color, loaded with `textureLoad`.

## mercury-temporal-mirror

- Kept: Viscosity, Reflection Strength, Mouse Impact, Metallic Sheen, K1/K2/GRAVITY, `STATE_TAG`, the wave step, the capillary packet, the Fresnel horizon, treble rain.
- Added: non-wetting meniscus — a small edge spring pulls height down, not a new Laplacian term; trough tarnish — negative height mixes toward a warm oxide. Crest specular stays.
- A packing: raw `(h, v, STATE_TAG, alpha)`. ACES on the display only.

## frosty-window

- Kept: Frost Density as the freeze rate, Crystal Size as scale, Blur Amount as warp, the Sparkle slider as the melt radius (the mapping the shader already had), voronoi facets, the 6-fold dendrite, frame nucleation, meltwater from above, the wet lens.
- Added: hoarfrost needles — the refraction offset steps along the nearest dendrite spoke; rime caps — branch tips mix toward opaque white. The glaze underneath stays.
- A packing: raw `(frost, water, caustic, alpha)`. ACES on the display only.

## encaustic-wax

- Kept: Brush Scale, Melt Intensity, Pigment Deposit, Relief, the three strata, viscous flow, the ridge light, canvas, the cooling bloom, the held-iron scrape, the wax grade curve.
- Added: heat soak — `A.b` decays in place and keeps viscosity behind the iron, trusted only when previous alpha is in the range this shader writes; scrape furrow — last frame's heat, off the cursor, lowers the ridge and shows the photo.
- A packing: telemetry `(ridge, pigment, soaked heat, alpha)`. The grade stays on the display. C is `textureLoad`.

## glass-wipes-coupled

- Kept: Rain Intensity, Fluid Viscosity, Wiper Size, Vortex Strength, the semi-Lagrangian step, gravity, wiper push, click impacts, hashed drops, evaporation.
- Added: vorticity confinement (§12.2D) from the curl already stored in `C.z`, scaled by Vortex Strength; glass beading — a capped sharpen toward drops, plus a wet streak the blade does not erase.
- A packing: raw `(vel.xy, vorticity, density)`. ACES on the display only.

## photonic-caustics

- Kept: Index of Refraction, Light Size, Chromatic Dispersion, Intensity, the depth normal, spectral bands, the Jacobian `1/|det J|`, click fronts, the Blinn-Phong glint, irradiance history.
- Added: soft inverse-square (§12.2F) — Light Size is `r0`, and it only raises the existing gaussian where the tail is longer; fold caustic — a ridge on `det J = 0`, split by the same per-channel IOR.
- A packing: raw irradiance rgb + caustic alpha. ACES on the display only. The photo is not written into A.

## virtual-lens

- Kept: Magnification, Lens Radius, Aberration, Edge Softness, the single magnification UV, the six-tap disc, the spectral tint, the Fresnel reflection, the rim, the core, the inner ring.
- Added: spherical aberration — the existing circle of confusion grows with `(dist/radius)²` times Aberration; cos⁴ vignetting (§12.2A) multiplies the existing edge darkening.
- A packing: ACES display RGBA. C is unread. No per-channel magnification UV.
