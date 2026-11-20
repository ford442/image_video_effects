# Idea Cards — Grok (optical / matter ten, 2026-11-20)

Written before the WGSL edits. Ten shaders the user listed by size. Each card adds two ideas in the existing main path. Saved `params` stay byte-exact. No shared spring, shockwave, or palette is added. Springs, click paths, and earlier ideas that are already in a file stay as they are.

Nine files still paste the binding header (everything except `mercury-temporal-mirror`). Migrating them to `#include "_prelude.wgsl"` is infrastructure and is not an idea.

Formula rule: a §12.2 row is newly applied on at most one file here.

- Vorticity confinement (§12.2D) is `glass-wipes-coupled` only.
- Soft inverse-square (§12.2F) is `photonic-caustics` only.
- cos⁴ vignetting (§12.2A) is `virtual-lens` only.
- No other §12.2 row is newly applied. Coefficient of finesse on `spec-iridescence-engine` deepens the two-beam sum already in that file; it is not the Airy-disc row and not a new thin-film motif.

```
SHADER: mouse-polarized-light-field
IDENTITY (one sentence): the photo seen through a mouse-aimed polarizer and a birefringent plate — Malus bands, interference color, moiré, click vortices.
KEEP VERBATIM: Polarization Angle / Birefringence / Fringe Density / Color Shift; localAngle from the pointer; Malus cos²(2θ); per-channel analyzer angles; hueShift by Color Shift; moiré; chromatic fringe spacing; treble shimmer; click vortices; analyzer flash.
MECHANISM INTERROGATION:
  tactic 2: a crossed polarizer has a dark isogyre. The cos² term is computed and then thrown away.
  tactic 3: malus is that discarded term. Luma is computed and not used as specimen thickness.
  tactic 6: C is unread. A stays display color. Do not invent a field.
ADD:
  1. Malus extinction — multiply the filtered field by the cos² term that was already computed, with a small leak so the isogyre is dark rather than a hole.
  2. Specimen optical path — retardation is birefringence times thickness. Luma stands in for specimen thickness, so the existing isochromes follow the photo.
FORBID: a spring, a new palette, per-channel UV splits that replace the analyzer, shockwaves beyond the vortices already here
A PACKING: ACES display RGBA (C unread; was display passthrough without ACES)
```

```
SHADER: spec-iridescence-engine
IDENTITY (one sentence): a thin film over the photo whose thickness follows depth, turbulence, the pointer, and click rings, colored by a spectral sum.
KEEP VERBATIM: Film Thickness / Film IOR / Intensity / Turbulence; the spring in extraBuffer[133..138]; spectral loop 380–700 nm; thickness from depth, noise, lens gaussian, held pointer, click rings; Fresnel mix; 8% C color trail.
MECHANISM INTERROGATION:
  tactic 1: the sum is two-beam cos. The next term for the same film is the Airy peak, which sharpens as IOR rises.
  tactic 8: the mix replaces the photo. A real film reflects some wavelengths and transmits the rest.
  tactic 6: C is display color. The 8% trail stays. Do not pack thickness into A.
ADD:
  1. Coefficient of finesse — keep the cosine; blend it toward a peak-normalized Airy shape by the reflectance of the existing Film IOR.
  2. Transmitted photo — bright bands take the photo out, dark bands leave it. Cover is still the existing Fresnel weight.
FORBID: a second spring, a new palette, replacing the spectral loop, oil-slick noise that ignores thickness
A PACKING: ACES display RGBA (C is the color trail)
```

```
SHADER: gen-turing-morphogenesis
IDENTITY (one sentence): spots, stripes, or labyrinth from an activator–inhibitor field, stained with the five-color organic ramp.
KEEP VERBATIM: Feed Rate / Evolution Speed / Pattern Scale / Color Shift; the three fk regimes; activatorInhibitor; coat grain along the activator gradient; inhibitor halo; chemical-front ridge; domain patches; mouse deposit; C color persistence; organic ramp.
MECHANISM INTERROGATION:
  tactic 3: the activator gradient is computed for the grain and then unused as an edge.
  tactic 6: C is display color. A stain can age along the same ramp without storing a new chemical.
  tactic 7: the gradient already has a direction; its magnitude is the front.
ADD:
  1. Chemical boundary — where that gradient is steep, the existing soft pattern threshold tightens. Interiors stay as they are.
  2. Stain aging — last frame's luma nudges Color Shift along the same ramp, so pigment that persisted goes browner. The slider still sets the global offset.
FORBID: a Gray-Scott solver swap, a new palette, a spring, reading C as a chemical field
A PACKING: ACES display RGBA (unchanged)
```

```
SHADER: aero-chromatics-prismatic
IDENTITY (one sentence): the photo blown into chromatic smoke by wind off the pointer, with a Cauchy prism at the mouse.
KEEP VERBATIM: Wind Force / Smoke Decay / Chromatic Split / Source Intensity; base wind plus mouse wind; curl shedding; per-channel history offsets and decay; Cauchy prism loop; Schlieren bend from speed.
MECHANISM INTERROGATION:
  tactic 2: real shedding is a street in the wake, opposite sense each side of the centerline, not a disc of curl on the pointer.
  tactic 8: faster air is lower pressure and holds less smoke. speedMag is already computed for Schlieren.
  tactic 6: C is advected color. The per-channel loads stay.
ADD:
  1. Kármán street — the existing curl is gated to the downstream wake and given an opposite gyre on each side of the centerline. Wind Force still scales the wind.
  2. Bernoulli thinning — high speedMag mixes the trail back toward the photo, so the slipstream clears and the slow wake keeps the smoke.
FORBID: a new prism model, a spring, replacing Cauchy or the Schlieren sample, a second advection buffer
A PACKING: ACES display RGBA (unchanged; C is that color)
```

```
SHADER: mercury-temporal-mirror
IDENTITY (one sentence): a liquid-metal mirror whose height and velocity obey a capillary wave equation, with click rings that travel on their own.
KEEP VERBATIM: Viscosity / Reflection Strength / Mouse Impact / Metallic Sheen; K1/K2/GRAVITY; STATE_TAG; the stride-1 and stride-2 wave step; capillary packet; Fresnel horizon and studio gradient; treble rain drops; A = raw (h, v, tag, alpha).
MECHANISM INTERROGATION:
  tactic 2: mercury does not wet the frame, so the contact line pulls down. Crests stay mirror-bright and troughs tarnish.
  tactic 5: name the artifact — non-wetting meniscus, oxide in the hollows.
  tactic 6: C is (h, v). The force has to be a tiny addend on the existing accel or the step goes unstable.
ADD:
  1. Non-wetting meniscus — near the frame, a small spring pulls height down. It is not a new stiffness on the Laplacian.
  2. Trough tarnish — negative height mixes toward a warm oxide and reflects less. Metallic Sheen still sets the mirror tint. Crest specular stays.
FORBID: changing K1/K2, storing display color in A, a spring cursor, replacing the horizon Fresnel
A PACKING: raw wave state (h, v, STATE_TAG, semantic alpha). ACES on the display only.
```

```
SHADER: frosty-window
IDENTITY (one sentence): frost that nucleates on the window frame and creeps inward, melted by the pointer into runnels that run down the glass.
KEEP VERBATIM: Frost Density → freeze rate, Crystal Size → scale, Blur Amount → warp, the Sparkle slider → melt radius (as the shader already maps it); voronoi facets; 6-fold dendrite; frame nucleation; neighbor growth; meltwater from above; wet lens; A = (frost, water, caustic, alpha).
MECHANISM INTERROGATION:
  tactic 2: hoarfrost needles follow the branch, and the tips go opaque white while the valleys stay a clear glaze.
  tactic 7: dend() already has a direction. The refraction offset is isotropic.
  tactic 6: C is (frost, water). The runnel advection stays. Do not ACES those fields.
ADD:
  1. Hoarfrost needles — the existing refraction offset gains a step along the nearest dendrite axis, stronger where the branch is.
  2. Rime caps — the bright tips of that branch mix toward opaque white. The facet glaze underneath stays the refractive frost.
FORBID: a new crystal lattice, a spring, replacing meltwater, rewiring the Sparkle slider off the melt radius
A PACKING: raw (frost, water, caustic, alpha). ACES on the display only.
```

```
SHADER: encaustic-wax
IDENTITY (one sentence): hot wax strata dragged over the photo, with a held pointer that irons a scrape and a bloom where the wax has cooled.
KEEP VERBATIM: Brush Scale / Melt Intensity / Pigment Deposit / Relief; three strata; viscous flow UV; impasto ridge and its light; canvas grain; cooling bloom; held-iron scrape; the wax grade curve.
MECHANISM INTERROGATION:
  tactic 2: encaustic wax holds heat, so the iron's path keeps flowing after the pointer leaves, and the tool leaves a groove.
  tactic 6: A is (ridge, pigment, heat, alpha) and was not read back. C can carry that heat without becoming color.
  tactic 5: the artifact is the soak and the furrow.
ADD:
  1. Heat soak — A.b decays in place and keeps the viscosity low behind the iron. The cursor heat is unchanged.
  2. Scrape furrow — last frame's heat, off the cursor, lowers the ridge and lets the photo show through until the wax cools.
FORBID: a new pigment solver, a spring, reading C as color, replacing the strata loop
A PACKING: telemetry (ridge, pigment, soaked heat, alpha). ACES-style grade on the display only. Heat is trusted only when the previous alpha sits in the range this shader writes.
```

```
SHADER: glass-wipes-coupled
IDENTITY (one sentence): rain on glass as a viscous velocity-and-density field, cleared by a pointer wiper, refracting the photo.
KEEP VERBATIM: Rain Intensity / Fluid Viscosity / Wiper Size / Vortex Strength; semi-Lagrangian step; gravity; wiper push and vortex; click impacts; hashed drops; evaporation; A = (vel.xy, vorticity, density).
MECHANISM INTERROGATION:
  tactic 3: vorticity is stored in C.z and never applied.
  tactic 2: water on glass beads, and a wiper leaves a wet streak rather than dry glass.
  tactic 6: C is the fluid. Confinement has to use the curl already stored.
ADD:
  1. Vorticity confinement (§12.2D) — N × ω from the stored curl, scaled by Vortex Strength, added to the existing velocity before the clamp.
  2. Glass beading — a capped sharpen toward drops, plus a thin residue in the wipe path so the blade does not erase to zero.
FORBID: replacing the semi-Lagrangian step, a spring, a second fluid, storing the photo in A
A PACKING: raw fluid (vel.xy, vorticity, density). ACES on the display only.
```

```
SHADER: photonic-caustics
IDENTITY (one sentence): a cursor light focused by the depth field into chromatic caustic ribbons on the photo.
KEEP VERBATIM: Index of Refraction / Light Size / Chromatic Dispersion / Intensity; depth normal; spectral bands; Jacobian 1/|det J| per channel; click fronts; irradiance history in A; Blinn-Phong glint.
MECHANISM INTERROGATION:
  tactic 2: a point light falls as 1/(d²+r0²). Light Size is that core. The fold of a caustic is the curve where det J is zero, which the gain already approaches.
  tactic 3: detJ is computed and then only inverted. The zero crossing is the visible ribbon.
  tactic 6: C is irradiance, not the photo. Do not write the display into A.
ADD:
  1. Soft inverse-square (§12.2F) — Light Size is r0. The existing gaussian aperture stays; the inverse-square raises it where the tail is longer.
  2. Fold caustic — a ridge on detJ = 0, split by the same per-channel IOR the Jacobian already uses.
FORBID: a new light motif, a spring, writing the photo into the irradiance history, replacing the Jacobian
A PACKING: raw irradiance rgb + caustic alpha. ACES on the display only.
```

```
SHADER: virtual-lens
IDENTITY (one sentence): a hand lens at the pointer — one magnification, a focal plane, a glass reflection of the surroundings.
KEEP VERBATIM: Magnification / Lens Radius / Aberration / Edge Softness; the single displaced UV (no per-channel split); six-tap disc defocus; spectral tint; Fresnel reflection; rim, core, inner ring.
MECHANISM INTERROGATION:
  tactic 2: a singlet is soft in the outer zone (spherical aberration) and the illumination falls as cos⁴ of the field angle.
  tactic 4: Aberration is a tint. The spatial version of that same slider is zone softness. Lens Radius is the field angle for cos⁴.
  tactic 3: dist/radius is already the rim parameter.
ADD:
  1. Spherical aberration — the existing circle of confusion grows with (dist/radius)² times the Aberration slider. The tint stays.
  2. cos⁴ vignetting (§12.2A) — the field falloff multiplies the existing edge darkening inside the glass.
FORBID: per-channel magnification UVs, a spring, a new lens shape, replacing the focal-plane disc
A PACKING: ACES display RGBA (C unread)
```
