# Optical / Glass / Holographic Ten — Idea Cards (written before WGSL)

Family: Optical, Glass, Holographic, and Prismatic effects (generative + advanced-hybrid).
Process Contract: `docs/SHADER_UPGRADE_BATCH.md` §0, §2, §7, §8.

---

SHADER: gen-holographic-lens-flare-matrix
IDENTITY: Infinite cellular grid of anamorphic holographic lens flares with blue-noise jitter, rotating chromatic dispersion stars, and horizontal streak spikes.
KEEP VERBATIM: Grid cellular partition, blue noise offset formula, streak calculation, chromatic angular star dispersion (angleR/angleB), raw sim state in A/C (persistentDensity, persistentStreak, persistentDistance, stateAlpha), all 4 params (intensity, speed, scale, mouse_influence).
ADD:
  1. Internal optical reflection ghosts — secondary and tertiary conjugate flare reflections along the optical vector connecting flare centers through the screen midpoint.
  2. Hexagonal aperture iris diffraction — six-blade iris diffraction spikes intersecting the anamorphic streak, modulated by scale and audio.
  3. Newton-ring thin-film interference fringes — circular interference rings around flare cores where coherent light reflects internally.
FORBID: Replacing the flare matrix with raymarching or liquid solvers.
A PACKING: raw sim state (persistentDensity, persistentStreak, persistentDistance, stateAlpha) matching HEAD's exact C reads.

---

SHADER: gen-holographic-plasma-geode
IDENTITY: Raymarched hollow crystalline geode enclosing an interior lined with KIFS fractal holographic crystals and a swirling volumetric plasma core.
KEEP VERBATIM: Rocky box/sphere SDF + cavity, 4-iteration KIFS crystal loop, volumetric plasma raymarch loop, cosine palette with holographic_hue, all 4 params (plasma_intensity, crystal_density, holographic_hue, core_rotation_speed), ACES display RGBA in A/C.
ADD:
  1. Internal crystal total internal reflection (TIR) with Cauchy chromatic facet dispersion — splitting transmitted light into spectral red, green, and blue rays upon entering crystals.
  2. Plasma filament electrical discharge arcs — branching high-energy dielectric breakdown arcs leaping between crystal spires across the central void.
  3. Agate mineral growth banding — concentric multi-layered mineral strata rings carved into the geode's rocky rim.
FORBID: Replacing the raymarched geode with 2D post-processing or generic screen-space fluid.
A PACKING: ACES display RGBA.

---

SHADER: gen-holographic-rainbow-surface
IDENTITY: Undulating heightfield surface exhibiting Wolfram thin-film iridescence, prismatic specular highlights, and spectral diffraction.
KEEP VERBATIM: FBM surface heightfield, thin-film formula (2 * n * d * cos(theta)), spectral diffraction highlights, mouse wave tilt, click ripple wavefronts, all 4 params (intensity, speed, scale, color_shift), ACES display RGBA in A/C.
ADD:
  1. Marangoni stress flow advection — swirling soap-bubble color whorls flowing along surface heightfield gradients driven by audio and speed.
  2. Multilayer variable-thickness interference gradient — physical soap film drainage profile producing rich color transitions from silvery-white to deep violet.
  3. Anisotropic micro-groove diffraction grating — ultrafine diffraction lines producing razor-sharp rainbow sheen streaks perpendicular to surface slopes.
FORBID: Raymarched 3D objects, spring cursors (it is a surface heightfield, not a pointer-held mass).
A PACKING: ACES display RGBA.

---

SHADER: gen-holographic-data-core
IDENTITY: Raymarched infinite quantum data core lattice with cyber-holographic data nodes, cylindrical bus conduits, volume Bragg diffraction, and Pepper's ghost reflection.
KEEP VERBATIM: Domain repetition, node SDF (boxes + cylinders), volume diffraction formula (volumeDiffraction, volumetricInterference), 60Hz flicker, saved params byte-exact, exact-C load.
ADD:
  1. Quantum logic bus photon packets — high-speed luminous energy pulses racing along the cylindrical data conduits between nodes.
  2. Hexagonal quantum containment lattice cage — delicate holographic wireframe cages pulsing around dense node clusters.
  3. Parallax holographic fringe interference — fine moiré interference fringe lines appearing between foreground and background lattice depths.
FORBID: Replacing the cybernetic data lattice with a photo filter or organic slime.
A PACKING: ACES display RGBA.

---

SHADER: gen-holographic-bismuth-core-reactor
IDENTITY: Raymarched stepped hopper-crystal bismuth fractal reactor with iridescent thin-film oxidation layers, orbiting micro-crystals, and pulsating core.
KEEP VERBATIM: 4-iteration 90-degree KIFS bismuth fractal folding (p = abs(p) - vec3(...) * core_scale), orbiting micro-crystals, mouse rot3D orientation, all 4 params (intensity, speed, scale, mouseInfluence), exact C loads.
ADD:
  1. Hopper-step terrace edge glow diffraction — distinct stepped right-angle crystalline ledge boundaries catching intense specular edge glints.
  2. Multi-order bismuth oxidation thin-film interference — physical refractive interference gradient mapping synthetic titanium-bismuth oxide film thicknesses across facet depths.
  3. Reactor magnetic containment field — transparent spherical energy confinement shield with pulsating geodesic flux lines.
FORBID: Destroying the 90-degree bismuth geometry or turning it into a generic Mandelbulb.
A PACKING: ACES display RGBA.

---

SHADER: chromatic-folds-bilateral
IDENTITY: Bilateral dream smoothing combined with chromatic hue folding along color gradients, warping the chromatic topology of the image.
KEEP VERBATIM: Bilateral filter loop with spatial and range weights, rgb2hsv / hsv2rgb color space conversions, foldHue math, saved params (fold_strength, pivot_hue, sat_scale, depth_influence), mouse distance influence.
ADD:
  1. Multi-spectral split folding — decouple R, G, and B hue fold pivots slightly along the chromatic gradient to generate prismatic dispersion fringes along fold ridges.
  2. Joint depth-bilateral preservation — integrate the depth buffer gradient into the range weight so sharp 3D geometry edges resist chromatic bleed.
  3. Continuous folding resonance wave — subtle standing wave oscillation along the fold contours modulated by audio bass/mids.
FORBID: Springs in extraBuffer (this is an edge-filtering photographic hybrid, not an interactive mass).
A PACKING: ACES display RGBA with exact textureLoad(dataTextureC, coord, 0) feedback (replacing previous filtered textureSampleLevel).

---

SHADER: aero-chromatics-prismatic
IDENTITY: Wind-driven chromatic smoke advection with physical prismatic Cauchy dispersion through a virtual refractive air-lens.
KEEP VERBATIM: Wind vector calculation from pointer displacement, cauchyIOR and wavelengthToRGB, 4-band spectral sampling loop, saved params (wind, decay, chroma, source), advection decay.
ADD:
  1. Aerodynamic vortex shedding — curl-noise turbulence inducing rolling vortex plumes along the advected wind wake.
  2. Schlieren optical gradient refraction — physical heated boundary layer refraction where air velocity gradients bend background light.
  3. Spectral dispersion feedback trails — differential wavelength feedback decay where long red wavelengths linger differently from blue in the wake.
FORBID: Replacing smoke advection with particle systems or fractals.
A PACKING: ACES display RGBA with exact textureLoad(dataTextureC, coord, 0) previous-frame persistence.

---

SHADER: glass-shatter-morph
IDENTITY: Voronoi shattered glass facets with pointer displacement, spring-damper inertia, and morphological erosion/dilation along fractured edges.
KEEP VERBATIM: Voronoi shard structure (voronoi), morphological min/max kernel, spring-damper cursor in extraBuffer[133..138], all 4 params (shard_scale, displacement, morph_blend, edge_width), ACES display RGBA packing.
ADD:
  1. Secondary micro-fracture spiderweb cracks — sub-cellular fracture lines branching recursively from Voronoi vertices.
  2. Prismatic total internal reflection (TIR) glints — razor-sharp spectral flashes along shard edges under steep grazing angles.
  3. Impact soundwave stress birefringence — isochromatic photoelastic fringe patterns radiating along glass fracture stress lines when clicked or struck by audio bass.
FORBID: Replacing the glass shards with particle explosions or liquid splashes.
A PACKING: ACES display RGBA.

---

SHADER: frosted-glass-lens-iridescence
IDENTITY: Microfacet frosted glass transmission with Beer-Lambert absorption, magnifying lens with chromatic aberration, and thin-film interference.
KEEP VERBATIM: Multi-tap microfacet scattering, Beer-Lambert absorption, thinFilmColor, spring-damper cursor in extraBuffer[133..138], all 4 params (frost_amount, lens_radius, edge_softness, film_ior), ACES display RGBA packing.
ADD:
  1. Microscopic condensation water droplets — stochastic surface dew beads with local meniscus refraction and highlight rims.
  2. Condensation wipe path — held pointer drag clears condensation and frost, leaving a transparent glass trail that gradually refrosts.
  3. Bevel prism dispersion — multi-spectral chromatic separation along the lens bevel contour using Cauchy dispersion.
FORBID: Replacing frosted glass with a generic kaleidoscope or neon glow filter.
A PACKING: ACES display RGBA.

---

SHADER: spec-prismatic-dispersion
IDENTITY: Physical 4-band Cauchy spectral dispersion through a curved glass lens with thickness absorption and chromatic glow.
KEEP VERBATIM: 4-band spectral sampling loop (cauchyIOR, wavelengthToRGB, refractThroughSurface), glass thickness absorption, spring cursor in extraBuffer[133..138], all 4 params (glass_curvature, cauchy_b, glass_thickness, spectral_saturation), ACES display RGBA.
ADD:
  1. Internal double-refraction caustic rings — secondary internal glass boundary reflection focusing caustics around the lens perimeter.
  2. Anti-reflective lens coating purplish-amber sheen — subtle multi-layer optical coating reflection on the glass surface.
  3. Chromatic radial distortion streaks — fine astigmatic streaks radiating from high-contrast highlight points under high curvature.
FORBID: Replacing physical dispersion with arbitrary color palettes or glitch blocks.
A PACKING: ACES display RGBA.
