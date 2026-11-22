# BRIEFS — fork A (liquid family), written BEFORE WGSL edits

Measured at HEAD (agents/mrchain.mjs, isolated solver, no ambient/fringe/click, seed 0.01): both a checkerboard and a low-k mode grow to the +-0.5 clamp by 300-900 frames. Flipping the gravity sign alone makes both modes stable; flipping only the capillary sign does not (capillary term is small). => RESCUE: gravity term +c2*lap(h), capillary term -sigma*biLap(h). With the correct sign heights stay ~0.01-0.05, so pass-2 normal gain (tuned for saturated +-0.5 noise) is re-calibrated (rescue, not an idea).
Floor/rescues for all four: exact textureLoad(dataTextureC) with clamped ints; 13-tap stencil reuse (lap + biLap from one tap set); wave speed made CFL-safe and visible (c2 = gravity*K, K chosen so max w*dt < 1.2).

---
SHADER: liquid-pass1
IDENTITY: capillary + gravity wave solver; clicks launch rings; ambient swell; raw state A=(h_prev,h_curr,velocity,age)
KEEP VERBATIM: A packing, depth gate (backgroundFactor), meniscus, analytic click packet, crest lean (idea 1 2026-10-17), Color Shift fringe (idea 2 2026-10-17), 4 saved params
ADD:
  1. Faraday parametric forcing — bass (plasmaBuffer[0].x) modulates the restoring term, g_eff = g(1 + e*bass*cos(2*w_k*t)), w_k from the file's own dispersion w^2 = c2 k^2 + s k^4 at the capillary wavelength; standing Faraday waves grow where drive = 2x natural. Native: vertical shaking of a capillary-gravity surface.
  2. Dispersive precursor — second click packet at wavenumber ~2.4x whose Gaussian-shell envelope travels at its own group velocity (capillaryWaveSpeed already in the file), so short capillary waves outrun the long train. Native: deep-water dispersion of the click.
FORBID: springs, extra ripple shockwaves, IQ palettes; repurposing the age channel
A PACKING: raw (h_prev, h_curr, velocity, age) — unchanged

SHADER: liquid-pass2
IDENTITY: refracting liquid sheet over the photo: Fresnel alpha, Beer absorption, caustic + wetting rim, ACES display
KEEP VERBATIM: height read from C.g (1 frame late by design), fold caustics + wetting rim (2026-10-17), alpha semantics, ACES, params
ADD:
  1. Sun glitter — Blinn facet specular from a fixed low sun, power ~300, treble (plasmaBuffer[0].z) sets the glitter density. Native: specular off capillary facets.
  2. Cauchy dispersion of the refraction — R/G/B photo taps at offsets scaled n(650/550/450nm), fringe grows with slope. Native: a refracting liquid disperses.
FORBID: holographic palettes, thin-film, springs
A PACKING: display ACES RGBA on writeTexture; does not write A

SHADER: liquid-optimized-pass1
IDENTITY: leaner branchless capillary solver; seiche beat + shore set-down (2026-10-17); turbidity adds drag
KEEP VERBATIM: branchless masks, packing, analytic click packet, seiche beat, shore set-down, params
ADD:
  1. Audio-forced slosh — bass drives the first lateral seiche mode of the basin: a += S*bass*cos(pi*uv.x)*sin(w_s t), w_s from the existing seiche rate. Native extension of the seiche idea. (Distinct from liquid-pass1's Faraday forcing.)
  2. Scale-selective viscous damping — nu*lap(v) from the four C.b neighbours; Damping+Turbidity set nu; high-k noise dies before long swells. Native: viscous decay of water waves ~ nu k^2.
FORBID: clones of liquid-pass1 ideas (parametric forcing, dispersive packet)
A PACKING: raw (h_prev, h_curr, velocity, age) — unchanged

SHADER: liquid-optimized-pass2
IDENTITY: leaner renderer: Snell offset along normal, velocity-stretched specular streak, ACES, Beer/Fresnel alpha
KEEP VERBATIM: Snell offset, streak, tangent sheen, alpha blend, ACES, params
ADD:
  1. Henyey-Greenstein in-scatter veil — turbid water scatters light toward the viewer along the sun direction; Turbidity (default 0) scales it, so default look is unchanged.
  2. Total internal reflection at steep crests — past the critical angle asin(1/1.33) the photo tap is replaced by a darkened mirror tap. Native: Snell's window.
FORBID: sun glitter / Cauchy fringe (liquid-pass2), audio in this render pass (audio lives in pass 1)
A PACKING: display ACES RGBA on writeTexture; does not write A
