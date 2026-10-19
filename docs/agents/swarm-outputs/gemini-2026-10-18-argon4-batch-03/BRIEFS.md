# Gemini Argon4 (`argon4/batch-03`) — Idea Cards

Batch date: `2026-10-18`
Shaders (10):
1. `gen-prismatic-cyber-chrono-nebula-peacock`
2. `gen-prismatic-quantum-fractal-nautilus-engine`
3. `gen-celestial-quantum-glass-dragonfly`
4. `gen-ethereal-quantum-holographic-fractal-coral`
5. `glass-refraction-prismatic`
6. `anamorphic-flare-iridescence`
7. `crystal-illuminator-iridescence`
8. `holographic-interferometry-bilateral`
9. `frosted-glass-lens-iridescence`
10. `dynamic-lens-flares-prismatic`

---

## 1. `gen-prismatic-cyber-chrono-nebula-peacock`
```
Shader: gen-prismatic-cyber-chrono-nebula-peacock (generative)
Kept: quantum glass body + KIFS folded feather train (featherFold), barbule thin-film interference (barbuleThinFilm), zoned ocellus eye-spots (ocellusZones), rachis-barb shafts (rachisBarbs), precessing ocellus halo (ocellusHalo), and click-ripple train rattle (shiver)
Added:
  1. Coronet crest aigrettes (sdCrestAigrettes, mat == 2.0) — a fan of 7 slender spatula-tipped crest quills atop the peacock head that sway with shiver/mids and carry iridescent turquoise-gold pennant bulbs
  2. Melanin photonic-crystal 2D rod-lattice Bragg shift & chrono-afterimage trail (braggRodLattice, chronoAfterimage via dataTextureC) — dual-order square/hex melanin rod-lattice Bragg interference across barbule tilt angle + upright orientation fix (uv.y flipped so head and train fan stand upright)
Touch: zoom_params.x..w unchanged (Plumage Spread, Quantum Glass Refraction, Nebula Density, Audio Reactivity); A = ACES display RGBA; exact dataTextureC read wired
```

## 2. `gen-prismatic-quantum-fractal-nautilus-engine`
```
Shader: gen-prismatic-quantum-fractal-nautilus-engine (generative)
Kept: logarithmic spiral shell (spiralMap), fractal inner chambers (chamberDist), mechanical greebles, auroral plasma core, view-angle cosine iridescence, subsurface spectral dispersion, fbm3 internal energy veins, and extraBuffer[0] bass envelope
Added:
  1. Calcified septa chamber bulkheads & central siphuncle osmotic conduit (septaWall, siphuncleTube, siphuncleGlow) — concave nacreous septa ribs partitioning the logarithmic spiral whorl and a luminous quantum siphuncle filament threading the chambers
  2. Aragonite nacre brick-and-mortar tablet interference & periostracum tiger-stripe flame banding (nacreBrickStack, tigerStripeMask) — multi-order Fabry-Perot reflection from ~500 nm stacked aragonite platelets combined with outer-whorl Nautilus flame stripes
Touch: zoom_params.x..w unchanged (Aura Intensity, Spiral Expansion, Fractal Depth, Audio Reactivity); migrated pasted header to #include "_prelude.wgsl"; A = ACES display RGBA
```

## 3. `gen-celestial-quantum-glass-dragonfly`
```
Shader: gen-celestial-quantum-glass-dragonfly (generative)
Kept: forewing/hindwing KIFS venation + trailing-edge vortex flutter (mapWings), thorax/head/segmented tail (mapBody), extraBuffer[133..138] spring-damper flight + velocity banking, Cauchy 3-band wing refraction + thin-film, hexagonal compound eye lattice, and tail quantum decoherence static
Added:
  1. Chitinous pterostigma wingtip counterweight & nodus flexion-hinge strut (pterostigmaMask, nodusCrease, costaRib) — dense amber-refractive leading-edge pterostigma cell near the wingtip and mid-wing nodus torsion notch with stress-birefringent gold/cyan tint
  2. Forewing/hindwing counter-stroking phase lag & dorsal ocelli / thoracic synth-muscle striations (wingPhaseLag, ocelliTriad, thoraxMuscleFibers) — biomechanical 90-degree phase lead between hindwings and forewings plus 3 dorsal simple ocelli on the vertex and glowing flight-muscle myofibril bands inside the glass thorax
Touch: zoom_params.x..w unchanged (Wing Frequency, Fractal Density, Refraction Index, Glow Intensity); A = ACES display RGBA with semantic wing/body alpha
```

## 4. `gen-ethereal-quantum-holographic-fractal-coral`
```
Shader: gen-ethereal-quantum-holographic-fractal-coral (generative)
Kept: KIFS fractal coral branches (map) with Voronoi organic noise, polyp mouth pits (pitSDF), swaying 3-stalk polyp tentacle tufts (gTuft), bass spawning bursts (gBurst), and zooxanthellae green breathing pulse from dataTextureC
Added:
  1. Radial sclerosepta corallite ridges & aragonite growth-ring bands (scleroseptaRidges, growthAnnuli) — 12-fold calcareous septa blades around each corallite pit and concentric skeletal calcification annuli along the branches
  2. Mesenterial filament GFP/RFP FRET fluorescence & overhead marine surface caustic web (fretEmission, seawaterCaustics) — donor-acceptor cyan-to-coral-orange fluorescence along high-curvature polyp rims illuminated from above by a refracted shallow-reef Voronoi caustic network
Touch: zoom_params.x..w unchanged (Fractal Density, Holographic Frequency, Bio-Luminescence Intensity, Audio Pulse Propagation); A = ACES display RGBA (alpha = branch coverage)
```

## 5. `glass-refraction-prismatic`
```
Shader: glass-refraction-prismatic (advanced-hybrid)
Kept: raymarched 3-sphere + ribbon smoothUnion glass SDF (map), 4-band Cauchy dispersion (450..680 nm), Fresnel dielectric reflection, Beer-Lambert absorption, internal edge glow, and extraBuffer[133..138] pointer spring
Added:
  1. Back-face exit march & critical-angle total-internal-reflection (TIR) prismatic fire (exitMarch, exitNormal, tirFire) — marches refracted rays through the glass interior to the rear interface for true two-surface Snell bending and critical-angle TIR rainbow bevel flashes
  2. Dispersion-focused spectral caustic convergence & Brewster-angle polarized reflection (causticJacobian, brewsterGlint) — surface-curvature convergence concentrates chromatic caustic filaments onto the refracted image while s/p Fresnel polarization sharpens Brewster-angle rim highlights
Touch: zoom_params.x..w unchanged (Transparency, Cauchy B Coefficient, Thickness Scale, Surface Roughness); migrated pasted header to #include "_prelude.wgsl"; A = ACES display RGBA
```

## 6. `anamorphic-flare-iridescence`
```
Shader: anamorphic-flare-iridescence (advanced-hybrid)
Kept: horizontal/vertical anamorphicStreak, hexagonal ghostElement train, centralGlow, 6-point starburst, rainbow halo ring, thinFilmColor interference, and extraBuffer[133..138] light spring
Added:
  1. Cylindrical front-element anamorphic squeeze bokeh (2:1 oval cat's-eye ghosts with mechanical vignetting) & multi-layer MgF2/TiO2 quarter-wave AR coating shift (anamorphicOvalBokeh, catsEyeClip, arCoatingTint) — authentic 2x anamorphic elliptical aperture ghosts that clip into peripheral cat's-eye crescents with per-element AR coating colors
  2. Horizontal streak Fraunhofer diffraction micro-comb & sensor microlens cross-grid glint (streakDiffractionComb, sensorGridGlint) — fine vertical interference striations and spectral wing dispersion along the horizontal anamorphic streak plus CMOS sensor microlens doublet reflections
Touch: zoom_params.x..w unchanged (Flare Intensity, Streak Length, Film Thickness, Film IOR); migrated pasted header to #include "_prelude.wgsl"; A = ACES display RGBA
```

## 7. `crystal-illuminator-iridescence`
```
Shader: crystal-illuminator-iridescence (advanced-hybrid)
Kept: 2D Voronoi crystal facets (min_dist, second_min_dist, cell_id), per-cell facet normal + dome curvature, extraBuffer[133..138] spring cursor lamp, Fresnel IOR, per-facet thinFilmColor, click ripples, and Beer-Lambert transmission alpha
Added:
  1. Uniaxial crystal birefringent double refraction (o-ray / e-ray optic-axis split) & crystallographic cleavage growth steps (opticAxis, birefringentSplit, cleavageTerrace) — per-grain crystal optic axis splits refracted rays into ordinary and extraordinary polarized images while rhombohedral cleavage steps terrace the facet normal
  2. Sub-facet internal reflection bounce between neighboring grain boundaries & fluid-inclusion sparkle (internalFacetBounce, inclusionGlint) — light grazing steep inter-grain boundaries reflects back across adjacent facets with golden-prismatic TIR and microscopic trapped fluid-inclusion glints
Touch: zoom_params.x..w unchanged (Cell Density, IOR Mix, Light Power, Film Thickness); migrated pasted header to #include "_prelude.wgsl"; A = ACES display RGBA
```

## 8. `holographic-interferometry-bilateral`
```
Shader: holographic-interferometry-bilateral (advanced-hybrid)
Kept: object + reference wave interferencePattern, spectralReconstruct rainbow, speckleNoise, 5x5 edge-preserving bilateral filter (smoothedHolo, edgeConfidence), parallax depth view offset, and extraBuffer[133..138] spring cursor
Added:
  1. Double-exposure holographic strain interferometry (phase-difference moire bullseyes & contour deformation fringes) (strainPhaseDelta, moireBeatFringe) — Lohmann/Powell-Stetson double-exposure beat fringes between unstressed and cursor/audio-deformed depth states mapping iso-strain contours
  2. Phase-singularity optical vortices (fork dislocations in the reference carrier) & Lippmann-Bragg volume-grating selectivity (forkDislocation, braggEnvelope) — topological charge m=+-1 phase singularities around depth edges/cursor probe that split carrier fringes into classic holographic fork dislocations
Touch: zoom_params.x..w unchanged (Fringe Density, Coherence Length, Reconstruction Angle, Color Saturation); migrated pasted header to #include "_prelude.wgsl"; A = ACES display RGBA
```

## 9. `frosted-glass-lens-iridescence`
```
Shader: frosted-glass-lens-iridescence (advanced-hybrid)
Kept: magnifying lens around smoothMouse (lensRadius, edgeSoftness), pointer-drag moisture wipe (wipeFactor), microscopic condensation droplet beads (dropMask), Beer-Lambert glass absorption, thinFilmColor coating, and lens bevel Cauchy dispersion
Added:
  1. Anisotropic dendritic ice-fern crystal needles on the frosted pane & 6-tap golden-angle Poisson microfacet scattering (iceFernCrystal, frostNormal, poissonScatter) — feathery 6-fold hexagonal ice-fern crystal ridges with multi-tap microfacet refraction replacing single-sample white-noise jitter
  2. Wiped-rim plowed condensation meniscus ridge & Newton's-ring air-gap interference inside the lens (wipeMeniscusBead, newtonRingPhase) — capillary water ridge accumulated along the edge of the pointer-wiped trail plus concentric plano-convex Newton's rings inside the lens aperture
Touch: zoom_params.x..w unchanged (Frost Amount, Lens Radius, Edge Softness, Film IOR); migrated pasted header to #include "_prelude.wgsl"; A = ACES display RGBA
```

## 10. `dynamic-lens-flares-prismatic`
```
Shader: dynamic-lens-flares-prismatic (advanced-hybrid)
Kept: multi-ghost optical train (i < maxGhosts) along center-smoothLight axis, 4-band Cauchy dispersion (refractThroughSurface), halo ring, 12-ray starburst, readTexture thresholded source color, and extraBuffer[133..138] light spring
Added:
  1. Polygonal iris diaphragm blades with edge-diffraction ringing & Petzval field-curvature coma tangents (irisPolygonGhost, comaStretch, fresnelRimRing) — 7-blade heptagonal aperture ghosts with Fresnel bright rims that stretch into off-axis sagittal/tangential coma wings toward frame corners
  2. Chromatic ciliary corona (wavelength-scaled Fraunhofer diffraction spikes + radial spectrum needles) (ciliaryNeedles, chromaticCorona) — hundreds of fine radial diffraction needles around the light source whose radial reach scales linearly with wavelength (450..680 nm)
Touch: zoom_params.x..w unchanged (Intensity, Threshold, Spread, Ghost Count); migrated pasted header to #include "_prelude.wgsl"; A = ACES display RGBA
```
