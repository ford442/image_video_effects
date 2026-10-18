# Optical / glass / holographic ten — idea cards (written before WGSL)

Ten optical, glass, and holographic generative shaders (`gen-holographic-data-core` through `gen-ice-crystal-lattice`). Each card preserves all existing ideas, modes, parameters, and A/C packing verbatim, and adds two native optical/crystallographic/fluid-optical ideas in the existing main path.

```
SHADER: gen-holographic-data-core
IDENTITY (one sentence): an infinite raymarched 3D lattice of hollow data cubes, inner floating cores, and orthogonal cylinder buses with volumetric Bragg/thin-film interference
KEEP VERBATIM: domain-repeated box/core/cylinder SDF, volumetricInterference (LAMBDA_R/G/B), logic bus photon energy packets, hexagonal quantum containment cage, depth parallax moiré fringe, scan packets, held-pointer beam, click rings, four sliders (nodeDensity, travelSpeed, dataPulseRate, glitchIntensity)
ADD (2–4 native ideas):
  1. corner-cube retroreflector bevels — trihedral corner chamfers on the outer data-cube shells bounce grazing view rays back with a high-order Bragg cyan-gold flash when the cell pulse is active
  2. bus-junction standing-wave nodes — stationary optical interference beads where the three orthogonal cylinder buses meet the outer cube wall
FORBID on this file: a new spring in extraBuffer, replacing the box/cylinder lattice with a different geometry
A PACKING: linear HDR display RGBA history in A (ACES on writeTexture)
```

```
SHADER: gen-holographic-fracture
IDENTITY (one sentence): iridescent cracked glass planes with radial SDF fracture lines from the center and spring-eased pointer, Voronoi shard edges, and click-launched fracture fronts
KEEP VERBATIM: radial sdSegment crack loop around center and spring-eased mouse (extraBuffer[133..137]), FFT bin 1..8 per-crack iridescence phase, click expanding ring + trailing spokes, Voronoi shard cell edges, huePreserveClamp + ACES display RGBA in A/C, four sliders (fractureCount, iridescence, crackWidth, pulseSpeed)
ADD (2–4 native ideas):
  1. Wallner stress-wave hackle arcs — faint curved sonic hackle ripples inside each shard sector bowed toward the bounding radial cracks
  2. birefringent photoelastic isochromatic fringes — cross-polarizer rainbow retardation bands concentrated in the high-stress zones around crack tips and shard corners
FORBID on this file: removing the existing spring or rewiring extraBuffer, replacing the 2D radial fracture plane with a 3D raymarcher
A PACKING: ACES display RGBA (hue-preserving clamp before tonemap; matches exact C read)
```

```
SHADER: gen-holographic-lens-flare-matrix
IDENTITY (one sentence): a blue-noise jittered matrix of holographic lens flares with anamorphic streaks, spinning star cores, conjugate optical reflection ghosts, 6-blade hex iris diffraction, and Newton rings
KEEP VERBATIM: grid cell flarePos with blueNoise2 offset, anamorphic streak, 4-point fastSin star core, conjugate ghosts (ghost1, ghost2), 6-blade hexagonal iris rays, Newton-ring fringes, RGB angular dispersion, readTexture motion composite, raw flare state in A/C, four sliders (intensity, speed, scale, mouse_influence)
ADD (2–4 native ideas):
  1. achromatic doublet cemented-interface halo — an annular Petzval caustic ring around each flare cell with radial red-inward / blue-outward chromatic splitting
  2. micro-lenticular sensor-grid satellite dots — discrete periodic grating diffraction pinpoints flanking the horizontal and vertical sensor axes of each bright flare core
FORBID on this file: tone-mapping dataTextureA (A/C must remain raw persistentDensity, persistentStreak, persistentDistance, stateAlpha), adding extraBuffer springs
A PACKING: raw sim state (persistentDensity, persistentStreak, persistentDistance, stateAlpha); ACES on writeTexture only
```

```
SHADER: gen-holographic-membrane
IDENTITY (one sentence): an undulating thin-film interference membrane whose height and surface normal drive two-layer iridescent reflection and depth-based peak/trough translucency
KEEP VERBATIM: multi-sine + fbm_mem height field, mouse view-angle shift and bulge/depression, click height/slope impulses, two-layer thinFilmIridescence + thinFilmIridescence2, rainbow sheen, peak/trough semantic alpha, raw [depthNorm, normal.x, normal.y, alpha] in A/C, four sliders (film_thickness, wave_frequency, undulation_amp, iridescence)
ADD (2–4 native ideas):
  1. Newton black-film drainage islets — where membrane troughs thin toward sub-wavelength drainage, destructive interference carves dark velvety patches bordered by a bright silvery-violet phase-step rim
  2. Plateau-border capillary veins — along saddle ridges where crossing wave trains meet, capillary suction thickens the film into luminous multi-order fringe veins
FORBID on this file: tone-mapping dataTextureA, replacing the height-field membrane with a 3D SDF
A PACKING: raw [depthNorm, normal.x, normal.y, alpha] in A/C; ACES on writeTexture only
```

```
SHADER: gen-holographic-plasma-geode
IDENTITY (one sentence): a raymarched rocky geode with a smooth-subtracted spherical cavity lined with KIFS fractal crystals and a swirling volumetric plasma core
KEEP VERBATIM: domain-repeated box/sphere rocky shell with cavity subtraction, 4-step KIFS cavity crystals, crystal Cauchy facet dispersion & TIR, agate mineral growth banding, 15-step volumetric plasma vortex + dielectric discharge arcs, mouse space warp + click shell/core shocks, four sliders (plasma_intensity, crystal_density, holographic_hue, core_rotation_speed)
ADD (2–4 native ideas):
  1. druzy quartz micro-sparkle collar — a bed of fine faceted quartz points along the rim where the banded agate shell meets the crystal cavity, catching rotating plasma glints
  2. piezoelectric phantom zoning — internal hexagonal growth-stage phantom planes inside the KIFS crystals that luminesce under bass and click compression
FORBID on this file: replacing the geode cavity with an open landscape, adding a spring in extraBuffer
A PACKING: ACES display RGBA
```

```
SHADER: gen-holographic-rainbow-surface
IDENTITY (one sentence): a liquid holographic surface with drainage-graded thin-film interference, Marangoni whorls, spectral diffraction highlights, and anisotropic micro-groove sheen
KEEP VERBATIM: smoothSurfaceHeight + computeNormal, mouse hover wave + plane tilt, click surface wave envelope, 3 directional lights, thinFilmIridescence with drainage gradient, Marangoni stress flow advection, spectralDiffraction + prismaticHighlight, anisotropic micro-groove diffraction grating, four sliders (intensity, speed, scale, color_shift)
ADD (2–4 native ideas):
  1. Rayleigh-Plateau ridge pearl beads — surface tension pinches high, low-slope wave crests into periodic micro-convex lens beads with crisp white-gold specular pips
  2. Brewster-angle polarization extinction band — where the local viewing angle crosses the thin-film Brewster angle, p-polarized glare extinguishes into a deep indigo band framed by saturated magenta-cyan fringes
FORBID on this file: a spring in extraBuffer, replacing the 2.5D height surface with a raymarcher
A PACKING: ACES display RGBA
```

```
SHADER: gen-hyper-geometric-void-glass-seraph
IDENTITY (one sentence): a 3D raymarched KIFS void-glass seraph folded around a central gravitational singularity with core twist and iteration-scaled chromatic dispersion
KEEP VERBATIM: rot3D mouse rotation, central singularity dSing + warpFactor, inner void core twist, 6-iteration KIFS fold + smin merge, Fresnel + refract glass shading with KIFS-iteration chromatic dispersion and cyan edge glow, four sliders (folding_scale, glass_refraction, singularity_mass, chromatic_aberration)
ADD (2–4 native ideas):
  1. six-wing seraphic feather-vane facets — beveled feather-barb ridges along three pairs of folded wing planes in the KIFS lattice that catch grazing gold-cyan Fresnel light
  2. singularity Einstein-ring gravitational lensing halo — rays grazing the central void singularity bend into a relativistic photon-sphere ring with Doppler blue/gold spin asymmetry
FORBID on this file: reading extraBuffer[0] as audio (use plasmaBuffer[0].xyz), replacing the KIFS + singularity SDF with a different fractal
A PACKING: ACES display RGBA (with exact dataTextureC temporal persistence)
```

```
SHADER: gen-hyper-rainbow-vortex
IDENTITY (one sentence): a multi-layered neon rainbow spiral vortex governed by a Rankine solid-body core and irrotational outer flow with differential-rotation history advection and a cyclostrophic condensation funnel
KEEP VERBATIM: Rankine swirl profile (coreR, omega), secondary mouse vortex, 3 counter-rotating spiralArm layers + treble fine interference, Rankine seam, counter-arm braid beads, differential-rotation back-advected C load, cyclostrophic pressure-deficit condensation funnel, click fronts, four sliders (intensity, speed, scale, colorShift)
ADD (2–4 native ideas):
  1. Kelvin-Helmholtz eyewall shear vortices — azimuthal m=6 polygonal sub-vortex roll-ups beaded along the velocity-gradient jump at the Rankine core boundary r = coreR
  2. Ekman boundary-layer spiral inflow streaks — logarithmic inward-drafting tracer filaments outside the core that spiral across the pressure gradient into the eyewall
FORBID on this file: tone-mapping dataTextureA before storage, adding an extraBuffer spring
A PACKING: raw HDR display RGBA history in A (pre-ACES), alpha = vortex energy; ACES on writeTexture
```

```
SHADER: gen-hyper-refractive-rain-matrix
IDENTITY (one sentence): a 3D raymarched matrix of falling, viscous-merged raindrops with OkLab/blackbody sky, bass lightning double-strobes, prismatic RGB drop dispersion, and fall-aligned streak history
KEEP VERBATIM: 3x3 neighbor smin capsule raindrop SDF with pointer repulsion, OkLab + blackbody + IQ cosine sky, lightningFlash double-strobe, per-channel eta RGB dispersion on drop rims, surface caustics, click caustic rings, fall-aligned upward history fetch in C, four sliders (rainDensity, dropSpeed, fluidViscosity, stormIntensity)
ADD (2–4 native ideas):
  1. Villermaux-Bossa aerodynamic basal flattening & capillary ripples — falling drops flatten on their windward bottom face with faint capillary oscillations that focus internal reflection caustics along the lower belly
  2. Descartes secondary internal-reflection rainbow glint — rays near the minimum-deviation angle inside each drop flare a concentrated spectral bow across the upper drop crown
FORBID on this file: tone-mapping dataTextureA (C is read as raw HDR rain), adding an extraBuffer spring
A PACKING: raw HDR rain RGB + coverage alpha in A/C (ACES on writeTexture only)
```

```
SHADER: gen-ice-crystal-lattice
IDENTITY (one sentence): a hexagonal 60-degree ice lattice with secondary dendrite needles, plate-vs-needle crystal habit, radial frost growth fronts, hoarfrost rime, and downward thermal melt pooling
KEEP VERBATIM: 3-axis hexagonal latticeLine web, branchNeedles + dendrite arms, plateFill interior habit, radial growthFront, pointer-held nucleation + localBranches, click radial fracture cracks, hoarfrost rime displacement, downward melt pooling in C, four sliders (latticeDensity, branching, growthSpeed, frostGlow)
ADD (2–4 native ideas):
  1. basal-facet stepped hopper terraces — concentric hexagonal vapor-deposition step risers recessed inside each crystal plate cell
  2. cross-polarized birefringence interference tints — uniaxial crystal orientation and plate thickness retard light into Michel-Lévy first-order gold, violet, and glacial-cyan interference bands along facet seams
FORBID on this file: tone-mapping dataTextureA, replacing the 2D hexagonal crystal lattice with a 3D cave
A PACKING: raw HDR display RGBA in A (ACES on writeTexture only)
```
