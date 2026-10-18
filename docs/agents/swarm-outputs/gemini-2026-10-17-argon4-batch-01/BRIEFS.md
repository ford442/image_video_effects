# Idea Cards — Gemini Argon4 (`argon4/batch-01`, 2026-10-17)

Contract: [`docs/SHADER_UPGRADE_BATCH.md`](../../../SHADER_UPGRADE_BATCH.md) (§0, §2, §7, §9).
Written **before** any WGSL edits.

---

## 1. `glass_refraction_alpha`

```
SHADER: glass_refraction_alpha
IDENTITY (one sentence): Raymarched three-blob smooth-union glass cluster in front of the source image with Snell entry/exit path length, Cauchy RGB dispersion, Beer-Lambert absorption, per-band caustic convergence, and physical transmittance alpha.
KEEP VERBATIM: map() 3-sphere smoothUnion glass cluster, entry + exit raymarch (enterT / exitT / interiorPath), Cauchy nR/nG/nB indices, per-band FFT caustic convergence, Beer-Lambert absorption, calculateAdvancedAlpha(), and saved params (transparency, dispersion, thickness, roughness).
ADD (2–4 native ideas):
  1. Exit-interface secondary refraction & critical-angle TIR bevel corona — evaluate the back-surface normal at exitT so rays undergo two-surface lens refraction and flare with a wavelength-split total-internal-reflection rim arc where grazing interior rays approach sin(theta_c) = 1/n(lambda).
  2. Smooth-union neck photoelastic stress birefringence — measure proximity to the coalescing bridge saddles between the three glass blobs and modulate a cross-polarized stress-retardation tint over interiorPath inside the fused glass necks.
FORBID on this file: Replacing the 3-blob glass lens over readTexture with an opaque generative scene, adding extraBuffer springs, or changing saved params.
A PACKING: ACES display RGBA in dataTextureA (existing dataTextureB normal/interiorPath write preserved).
```

---

## 2. `gen-holographic-data-core`

```
SHADER: gen-holographic-data-core
IDENTITY (one sentence): Infinite 3D raymarched quantum lattice of hollow holographic data cubes, inner floating cores, and 3-axis logic cylinders with volumetric thin-film/Bragg interference, corner-cube retroreflector bevels, and bus-junction standing-wave nodes.
KEEP VERBATIM: map() domain-repeated hollow box + inner core + 3-axis cylinders (mat_id 1/2/3), volumetricInterference(), logic bus photon packets, hexagonal containment cage, corner-cube retroreflector bevels, bus-junction standing-wave nodes, pointer laser, click data rings, and saved params (nodeDensity, travelSpeed, dataPulseRate, glitchIntensity).
ADD (2–4 native ideas):
  1. Inner-core Bragg memory-page strata — inside each floating inner core (mat_id == 2.0), stacked volumetric recording planes diffract the view ray by Bragg angle into high-density RGB optical memory lamellae that scroll with cell pulse phase.
  2. True Pepper's-ghost beamsplitter parallax double-reflection — replace the scalar PEPPER_GHOST_REFLECTION dimming with a 45-degree glass-beamsplitter parallax offset reading dataTextureC at a depth-shifted coordinate with dichroic cyan/magenta plate tint.
FORBID on this file: Changing the cubic data-node lattice into an organic or fluid scene, adding extraBuffer state, or altering saved params.
A PACKING: Linear HDR display RGBA history in dataTextureA (ACES tone-mapped on writeTexture).
```

---

## 3. `gen-minimal-surface-soap-iridescence`

```
SHADER: gen-minimal-surface-soap-iridescence
IDENTITY (one sentence): Parametric minimal surface morphing continuously between catenoid and helicoid via Bonnet rotation, shaded with view-dependent soap-film interference, gravity drainage with Marangoni plumes, Newton black film at the top, and Culick rupture holes on click.
KEEP VERBATIM: surfacePoint() / surfaceTangentU() / surfaceTangentV() catenoid-helicoid Bonnet morph, analytic normal N = normalize(cross(pu, pv)), Mysels gravity drainage + Marangoni plumes + Newton blackFilm, Culick click rupture holes with Rayleigh-Plateau beaded rims, and saved params (bonnetRotation, surfaceTension, yRotation, causticGlow).
ADD (2–4 native ideas):
  1. Bonnet-rotated asymptotic geodesic surfactant web — minimal surfaces (H = 0) carry orthogonal asymptotic curves in (u, v) that rotate by bonnet/2 during the catenoid-to-helicoid morph; surfactant accumulation along these asymptotic lines shifts local film thickness and phase.
  2. Multi-bounce Airy finesse interference & projected fold caustics — augment the single-order HSV soap film with a high-finesse Airy multiple-reflection harmonic (4F sin^2(delta/2) / (1 + 4F sin^2(delta/2))) that sharpens at grazing NdotV and brightens along projected surface folds (screenPos).
FORBID on this file: Replacing the analytic minimal surface with a 3D raymarcher or 2D flat noise plane, adding extraBuffer state, or altering saved params.
A PACKING: ACES display RGBA in dataTextureA.
```

---

## 4. `liquid_crystal_birefringence`

```
SHADER: liquid_crystal_birefringence
IDENTITY (one sentence): Twisted-nematic liquid-crystal cell over the source image between crossed polarizers (Malus's law), with a spring-damped topological defect core under the cursor, 8-bin FFT Newton retardation rings, click voltage fronts, and asymmetric Frederiks relaxation lag in dataTextureC.
KEEP VERBATIM: schlierenTexture(), directorField(), phaseRetardation(), rotatePolarization(), birefringenceColor(), spectralFringe(), clickVoltagePulse(), malusTransmission(), extraBuffer[133..134] defect core spring, asymmetric Frederiks relaxation lag from dataTextureC, and saved params (cell_thickness, twist_angle, birefringence, voltage).
ADD (2–4 native ideas):
  1. Conoscopic Maltese-cross isogyres & melatope rings around the defect core — in convergent polarized light around mousePos, render the four dark extinction arms (cos^2(2*(azimuth - analyzerAngle))) crossed by concentric polychromatic melatope retardation rings that rotate with the held analyzer.
  2. Extraordinary-ray birefringent double-refraction walk-off — sample the ordinary (o) ray at uv and the extraordinary (e) ray displaced along the local nematic director by localBirefringence * effectiveThickness, blending o and e images by director polarization projection so high-Delta-n regions exhibit true calcitic/nematic double refraction.
FORBID on this file: Removing readTexture image transmission, replacing the Mueller/Malus polarization model, or altering saved params.
A PACKING: ACES display RGBA in dataTextureA (read back via exact textureLoad for Frederiks relaxation lag).
```

---

## 5. `photonic-caustics-iridescence`

```
SHADER: photonic-caustics-iridescence
IDENTITY (one sentence): Backward 12-photon-traced dispersive caustics from a spring-damped area light over depth+FBM surface normals, accumulated temporally in dataTextureC to illuminate a multi-wavelength thin-film iridescent layer over the refracted source image.
KEEP VERBATIM: getSurfaceNormal() from readDepthTexture + FBM, extraBuffer[133..138] area-light spring + click impulse, 12-photon loop with iorR/iorG/iorB Snell refraction, thinFilmColor() 390..690nm spectral integration, refracted readTexture composite, and saved params (ior, lightSize, dispersion, intensity).
ADD (2–4 native ideas):
  1. Catastrophe-optics fold & Pearcey cusp Airy supernumerary fringes — detect caustic fold gradients where the surface normal curvature concentrates photons and modulate multi-wavelength Airy diffraction fringes on the bright side of each caustic filament.
  2. Subsurface depth-bounce secondary caustic aureole — trace a second internal reflection off the underlying scene depth relief (readDepthTexture) displaced along the refracted normal, adding a dispersion-tinted subsurface photon halo around primary caustic cusps.
FORBID on this file: Replacing the 12-photon backward tracer or removing readTexture / readDepthTexture coupling.
A PACKING: ACES display RGBA in dataTextureA (with accumulated photonic caustics and thin-film sheen).
```

---

## 6. `iridescent-oil-slick`

```
SHADER: iridescent-oil-slick
IDENTITY (one sentence): Flowing oil-on-water thin-film interference integrated across 8 visible wavelengths (Newton black film at 0 nm, first-order gold-magenta-blue, pastel higher orders) with hexagonal Marangoni cell ridges and an advected finger-push black-film disc stored in A.a.
KEEP VERBATIM: snoise() / fbm() flow, thinFilmInterference() 8-wavelength Gaussian integration, hexPattern() + hexWall() Marangoni ridges, PUSH_SENTINEL (4.0) + push disturbance in dataTextureA.a advected from dataTextureC.a, hue rotation matrix, and saved params (filmScale, flowSpeed, turbulence, colorShift).
ADD (2–4 native ideas):
  1. Ostwald-ripened dewetting oil microlenses ("eyes") inside hex cells — form parabolic convex oil droplets at hex-cell centers surrounded by a depleted capillary moat, producing tight concentric Newton interference rings inside each oil eye.
  2. Click-triggered surfactant spreading fronts & upstream RGB sheen advection — click ripples launch expanding Marangoni surfactant rings that thin the interior into silvery low-order film while piling a rainbow collar at the wave front, and advect pre-ACES film RGB from dataTextureC.rgb along upCoord.
FORBID on this file: Breaking the PUSH_SENTINEL + push alpha packing in dataTextureA.a, adding extraBuffer state, or altering saved params.
A PACKING: rgb = pre-ACES display RGB (now advected with viscous sheen memory), a = 4.0 + finger-push disturbance [0..1] (sentinel-offset raw state).
```

---

## 7. `gen-celestial-prism-orchid`

```
SHADER: gen-celestial-prism-orchid
IDENTITY (one sentence): Raymarched 3D folded fractal crystal orchid with capped-cone petals, bioluminescent nutrient veins, radiant starburst core, Cauchy petal-edge dispersion, starlight stamen dust, and a spring-damped pollinator cursor in extraBuffer[133..138].
KEEP VERBATIM: 5-iteration folded sdCappedCone petal + sdCapsule vein SDF, mat_id 0 (core) / 1 (petals), extraBuffer[133..138] pollinator spring, Cauchy etaR/G/B specular dispersion, micro-venation nutrient pulses, stamen dust, click petal rings, and saved params (bloom_complexity, refractive_index, core_intensity, cosmic_wind_speed).
ADD (2–4 native ideas):
  1. Labellum ultraviolet-to-gold nectar-guide chevrons — on the lower inner lip petals (p.y < 0.0), project bilateral structural-interference chevron striae that guide toward the floral center and intensify as the pollinator approaches.
  2. Five-fold floral column internal caustics & golden pollinia filament — focus core light through the inner petal bases into 5-fold refractive caustic cusps, and arc a glowing golden pollinia pollen-tether between the orchid column and the sprung pollinator cursor.
FORBID on this file: Replacing the folded cone orchid SDF with a 2D flower or non-botanical fractal, or changing saved params.
A PACKING: ACES display RGBA in dataTextureA.
```

---

## 8. `gen-ethereal-glass-flora-terrarium`

```
SHADER: gen-ethereal-glass-flora-terrarium
IDENTITY (one sentence): Raymarched botanical greenhouse of smooth-blended glass stems, nodal joints, unfolding petals, internal capillary nectar lumens, and swirling pollen spheres inside a condensation-beaded glass terrarium sphere.
KEEP VERBATIM: glassBranch() (stem + 3 joints + 4 unfolding petals), lumenBranch() / lumenField() capillary nectar packets, 12 swirling pollen spheres (mat = 2.0), raymarchChromatic() 12-step interior glass march with bgHaze() dispersion, dewMeniscus(), condensationDroplets(), and saved params (flora_density, nectar_glow, refraction_index, time_warp).
ADD (2–4 native ideas):
  1. Geodesic terrarium glass-dome mullions & click-driven acoustic mist rings — make the existing 4.0-radius terrarium container sphere visible as a faceted botanical conservatory dome with grazing thin-glass Fresnel double-reflections, brass/glass geodesic ribs, and click ripples travelling across the curved shell.
  2. Pinnate leaf-blade venation & stomatal spore-pore luminescence — etch midrib and lateral secondary veins across the unfolding glass petals with glowing micro-stomatal pores that pulse with nectarGlow and release warm bioluminescent mist into the interior march.
FORBID on this file: Replacing the 3D raymarched glass flora + pollen scene, adding extraBuffer state, or changing saved params.
A PACKING: ACES display RGBA in dataTextureA.
```

---

## 9. `gen-liquid-rainbow-glass`

```
SHADER: gen-liquid-rainbow-glass
IDENTITY (one sentence): Multi-layer flowing liquid rainbow art glass with oil-film interference, meniscus rainbow rims at the liquid lip, divergence-based refraction caustic webs, rising micro-bubbles, and viscous pointer-stirred history in dataTextureC.
KEEP VERBATIM: 9-layer composite (bgGrad, liquidLayer 1/3/4, oilFilm, meniscus rims, glassRefraction + caustic divergence web, chromatic dispersion bubbles, rising micro-bubbles, edge glow, ribbons, bright caustics, mouse vortex stir), viscous rotational back-sampling of dataTextureC, Sellmeier edge aberration, and saved x-meta params (Intensity, Speed, Scale, Color Shift).
ADD (2–4 native ideas):
  1. Hand-blown murrine glass-cane striae (cord) — stretch fine high-index silicate striae along the shear tangent of the flowing liquid layers and wire the dormant chromaticDispersion() helper to give each glass cane internal RGB thread dispersion.
  2. Dichroic gold-ruby / cyan-violet transmission-reflection shift & click-dropped molten glass gathers — shift thick interior liquid pools toward warm gold-ruby transmission while steep refractive gradients glint with complementary cyan-violet dichroic reflection, and let click ripples drop expanding lenticular gathers of hot glass that bend the underlying layers.
FORBID on this file: Replacing the multi-layer 2D liquid-glass flow with a 3D SDF scene, adding extraBuffer state, or altering the JSON parameter schema.
A PACKING: Display-history RGBA in dataTextureA (temporal = mix(prev.rgb * 0.96, color, 0.25) read via swirled integer textureLoad from dataTextureC).
```

---

## 10. `gen-prismatic-cyber-aether-void-kitsune`

```
SHADER: gen-prismatic-cyber-aether-void-kitsune
IDENTITY (one sentence): Raymarched cybernetic crystal nine-tailed fox (body/head/snout/ears/armor/shoulder octahedra with hex runes, nine waving thin-film aether tails with analytic kitsune-bi fox-fire tips and inter-tail streamers, orbiting octahedral shard swarm, and stacked auroral torus rings) in a kaleidoscopic volumetric void storm.
KEEP VERBATIM: map() 4-material scene (1 = body + hex runes, 2.x = 9 tails with thin-film spectrum, 3 = octahedral shard swarm, 4 = 3 torus rings with moire gate), analytic foxFire() and tailBridgeStreamers(), kaleido() volumetric storm background, and saved params (tailDispersion, currentWarp, stormDensity, runeGlow).
ADD (2–4 native ideas):
  1. Levitating Hoshi-no-tama (star-ball prism orb) & kabuki cyber-visor eye markings — place a refractive star-ball jewel floating ahead of the kitsune's snout (mat_id = 5.0) that casts prismatic caustics onto the head/shards, paired with glowing crimson-cyan kitsune visor eye-slits and facial crest markings on p_head.
  2. Dispersive 3-channel shard-facet laser diffraction & temporal aether wake in dataTextureC — split reflections off the orbiting octahedral shards (mat_id == 3.0) into 3-wavelength Cauchy prism beams, and wire exact textureLoad(dataTextureC, pixel, 0) temporal feedback so the nine tails, fox-fire, and shards leave a decaying aether spirit-wake.
FORBID on this file: Replacing the 9-tailed cyber-kitsune SDF scene, adding extraBuffer state, or changing saved params.
A PACKING: Display RGBA in dataTextureA (now read back from dataTextureC for temporal aether spirit-wake persistence).
```
