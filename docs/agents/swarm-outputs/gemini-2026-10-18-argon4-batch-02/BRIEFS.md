# Idea Cards & Mechanism Interrogation — Gemini Argon4 (`argon4/batch-02`)

**Swarm:** `gemini-2026-10-18-argon4-batch-02`
**Date:** 2026-10-18
**Contract:** `docs/SHADER_UPGRADE_BATCH.md` (`§1`–`§12`)

---

## 1. `gen-prismatic-crystal-growth` (`public/shaders/gen-prismatic-crystal-growth.wgsl`)
- **WHAT IS THIS**: 3D SDF raymarched lattice of growing octahedral and dodecahedral crystals over a ground plane (`p.y + 2.0`), with Cauchy facet fire, oscillatory growth-zone shells, hopper face recesses, and re-entrant twin notches.
- **MECHANISM INTERROGATION (§12.1)**:
  - *Primary mechanism*: Domain-repeated `crystalLattice(p, t, growth, spacing)` mixing `sdOctahedron` and `sdDodecahedron` over a ground plane (`mat < 0.1`), shaded with `cauchyFire` and `growthZoning`.
  - *Missing native detail*: The ground plane (`mat < 0.1`) is currently a flat unpatterned grey slab (`vec3(0.08, 0.1, 0.15) * (diff * 0.5 + 0.2)`) that receives zero refracted caustic light from the crystal lattice above it, and the crystal edges lack physical cleavage-bevel curvature glints and Beer–Lambert depth attenuation.
- **FORMULA ADMISSION (§12.2 / §12.4)**:
  - **Idea 5**: *Tetrahedral Curvature Cleavage-Edge Bevel Glints (`§12.2E Tetrahedral curvature`)* — Compute 4-tap tetrahedral SDF curvature `calcCrystalCurvature` on crystal hits (`mat >= 0.1`) to highlight sharp octahedral/dodecahedral facet ridges with macrostep bevel glints.
  - **Idea 6**: *Beer-Lambert Crystal Interior Absorption & Ground-Plane Projected Prismatic Caustic Carpet (`§12.2F Beer–Lambert absorption`)* — Apply `exp(-thickness * (1.0 - crystalCol) * 2.2)` Beer–Lambert absorption through the crystal body and project a 3-wavelength refracted caustic lattice onto the ground plane (`mat < 0.1`).

## 2. `gen-luminescent-quantum-glass-phoenix-egg` (`public/shaders/gen-luminescent-quantum-glass-phoenix-egg.wgsl`)
- **WHAT IS THIS**: Raymarched ovoid glass shell (`mapEgg`) enclosing a volumetric FBM plasma embryo core (`mapCore`) with Voronoi shell cracks (`crackEdge`), caustic threads, hatching pip (`PIP_DIR`), feather-barb filaments, and raw `dataTextureA/C` ember heat persistence.
- **MECHANISM INTERROGATION (§12.1)**:
  - *Primary mechanism*: Outer shell raymarch (`mapEgg`) followed by refracted 64-step internal volumetric raymarch (`mapCore`) accumulating `colCore` and `density`.
  - *Missing native detail*: The internal volumetric core scatters light isotropically without phase-angle dependence relative to `keyLight` and lacks the twisted chalaza suspension cords and blunt-end sub-shell air cell characteristic of an avian egg; outer Voronoi cracks also lack 3D crevice occlusion.
- **FORMULA ADMISSION (§12.2 / §12.4)**:
  - **Idea 6**: *Anisotropic Henyey-Greenstein Embryo Scattering & Twisted Chalaza Suspension Filaments (`§12.2F Henyey–Greenstein phase`)* — Weight internal core emission by `hgPhase(dot(rdIn, keyLight), 0.58)` and add helical polar chalaza suspension cords (`chalaza`) anchoring the core along the egg's Y axis.
  - **Idea 7**: *5-Tap Eggshell Crack Crevice AO & Blunt-End Air-Cell Meniscus (`§12.2E 5-tap AO`)* — Compute `aoFive` along the egg shell normal (`eggAO`) to ground surface reliefs and add a translucent air-cell chamber meniscus (`airCellMeniscus`) at the upper pole (`p.y > 0.78`).

## 3. `gen-chromatic-glass-lattice` (`public/shaders/gen-chromatic-glass-lattice.wgsl`)
- **WHAT IS THIS**: Raymarched 3D domain-repeated glass box+octahedron lattice with cross-braces, growth spurs, Voronoi mouse shatter, Cauchy dispersion, internal TIR raymarching, and photoelastic stress birefringence.
- **MECHANISM INTERROGATION (§12.1)**:
  - *Primary mechanism*: `raymarchChromatic` marching `map()` (`opRep` box/octahedron/brace/spur SDF), computing 3-wavelength `refractRay` and an 8–16 step internal raymarch (`it`).
  - *Missing native detail*: The internal raymarch uses flat constant colour rather than exponential Beer–Lambert glass absorption along the internal optical path `it`, and the strut intersections lack SDF curvature bevel highlights and Airy diffraction rings around the glowing node cores.
- **FORMULA ADMISSION (§12.2 / §12.4)**:
  - **Idea 6**: *Tetrahedral Curvature Beveled Strut Ridges & Airy Diffraction Node Rings (`§12.2E Tetrahedral curvature`, `§12.2F Airy ring`)* — Evaluate tetrahedral SDF curvature (`strutCurvature`) on hit to accent chamfered glass strut edges and modulate node core flares with an `airyDisc` diffraction ring pattern.
  - **Idea 7**: *Beer-Lambert Optical Path Absorption & Internal Waveguide Core Modes (`§12.2F Beer–Lambert absorption`)* — Track total internal optical path length `it` inside the glass struts to attenuate transmitted light via `exp(-it * vec3(0.45, 0.18, 0.08))` while standing waveguide modes pulse along the strut axes.

## 4. `gen-ethereal-quantum-hologram-bonsai` (`public/shaders/gen-ethereal-quantum-hologram-bonsai.wgsl`)
- **WHAT IS THIS**: Raymarched L-system cylinder bonsai tree (`bonsaiSDF`) with trunk, multi-level branches, root system, quantum superposition branch collapse (`branchPresence`), prune-cut seal rings, north-facing moss, and 3D sap pulse.
- **MECHANISM INTERROGATION (§12.1)**:
  - *Primary mechanism*: `bonsaiSDF` combining `bonsaiBranch` cylinders and `sdSphere` leaf droplets via `smin`, shaded with jade-magenta holographic iridescence, moss, and sap pulse.
  - *Missing native detail*: Branch forks and root-flare hollows lack 3D ambient occlusion (`aoFive`) to separate overlapping boughs, and the canopy space around the branches has no drifting quantum sakura/leaf motes or twisted jin deadwood grain striations.
- **FORMULA ADMISSION (§12.2 / §12.4)**:
  - **Idea 5**: *5-Tap Bonsai Bough Crevice AO & Helical Shari Deadwood Grain Striations (`§12.2E 5-tap AO`)* — Compute 5-tap `aoFive` along the bark normal to shade branch forks and root hollows, plus helical shari/jin deadwood grain striations twisting up the trunk and branches.
  - **Idea 6**: *Orbit-Trap Quantum Sakura Blossom Motes in Canopy Space (`§12.2E Orbit trap`)* — Accumulate an orbit-trap volumetric field of drifting holographic sakura blossom motes (`sakuraMotes`) along the ray within the canopy volume (`length(p - vec3(0.0, 0.8, 0.0)) < 1.8`).

## 5. `liquid-prism-cascade` (`public/shaders/liquid-prism-cascade.wgsl`)
- **WHAT IS THIS**: 2D image-processing artistic shader performing a 3-stage iterative RGB Cauchy refraction cascade driven by luminance gradients and depth curvature, with critical-angle Snell TIR rim sparkle.
- **MECHANISM INTERROGATION (§12.1)**:
  - *Primary mechanism*: 3-stage loop (`for (var stage = 0; stage < 3; stage++)`) advancing per-channel UVs `chUV[ch]` along `prismOffset` and blending layers (`0.55 / 0.28 / 0.17`), followed by `snellExit` critical-angle TIR glints.
  - *Missing native detail*: The luminance gradient uses 2-tap axial differences (`lumR - lumL`, `lumU - lumD`) which alias on diagonal edges, and the 3-stage cascade + shimmer can overshoot local image extrema on high-contrast boundaries without an anti-halo morphological envelope.
- **FORMULA ADMISSION (§12.2 / §12.4)**:
  - **Idea 3**: *Isotropic Sobel-3×3 Meniscus Ridge Normals & Capillary Wavelet Caustics (`§12.2A Isotropic Sobel 3×3`)* — Upgrade the stage-0 luminance gradient to a rotation-invariant 3×3 Sobel operator (`sobelGrad`) and focus bright liquid meniscus caustic lines where the Sobel gradient magnitude peaks.
  - **Idea 4**: *Anti-Halo Envelope Clamp & Temporal Cascade Trail (`§12.2A Anti-halo envelope`)* — Compute local 4-neighbor min/max bounds (`localMin`, `localMax`) around `uv` to bound the soft-light prism composite (`clamp(finalRGB, localMin - span, localMax + span)`) and blend subtle `dataTextureC` liquid persistence.

## 6. `optical-feedback` (`public/shaders/optical-feedback.wgsl`)
- **WHAT IS THIS**: Interactive recursive optical feedback tunnel reading `dataTextureC` via `feedbackBilinear` at zoomed, rotated, domain-warped UVs around a spring-damped cursor, with multi-front click shockwaves and 8-band FFT spectral hue rings.
- **MECHANISM INTERROGATION (§12.1)**:
  - *Primary mechanism*: Recursive coordinate transform (`scaled`, `domainWarp`, `shockwave`) sampling `dataTextureC` (`feedbackBilinear`), rotating HSV hue per radial FFT zone, and writing back to `dataTextureA`.
  - *Missing native detail*: Repeated bilinear resampling of `dataTextureC` gradually blurs fine tunnel edges over many feedback generations unless counteracted by an isotropic Laplacian unsharp/reaction-diffusion term, and the optical cavity lacks Fabry-Pérot mirror interference fringes between the current frame and the delayed feedback wave.
- **FORMULA ADMISSION (§12.2 / §12.4)**:
  - **Idea 3**: *9-Point Isotropic Laplacian Turing-Edge Restorer on Feedback Buffer (`§12.2D 9-point Laplacian`)* — Evaluate the 9-point isotropic Laplacian (`lap9Feedback`) on `dataTextureC` at the warped feedback coordinate to inject crisp reaction-diffusion edge filaments that prevent multi-generation bilinear wash-out.
  - **Idea 4**: *Fabry-Pérot Optical Cavity Mirror Interference Fringes (`§12.2F Thin-film interference`)* — Compute multi-beam Fabry-Pérot Airy interference (`1.0 / (1.0 + finesse * sin(opticalPhase)^2)`) from the phase difference between `current.rgb` and `feedbackSample.rgb` across the tunnel's radial optical path.

## 7. `bubble-lens` (`public/shaders/bubble-lens.wgsl`)
- **WHAT IS THIS**: Interactive thin-film soap bubble lens (`evalBubble`) with Marangoni counter-rotating swirls, 8-band FFT drum-mode membrane resonance, Newton black-film spots, concave rear-wall inverted reflection, and click-spawned satellite bubbles.
- **MECHANISM INTERROGATION (§12.1)**:
  - *Primary mechanism*: `evalBubble` computing radial lens magnification, 2-vortex Marangoni swirl on `filmUV`, 8-bin FFT drum modes on `drainedThickness`, cosine interference, and concave rear-wall reflection.
  - *Missing native detail*: The forward transmission uses a scalar polynomial `(1.0 - factor^2)` rather than 3-wavelength 3D vector Snell refraction through the curved spherical soap film, and the primary specular highlight lacks an Airy diffraction ring and Plateau-border capillary meniscus ring at the bubble rim (`factor -> 1.0`).
- **FORMULA ADMISSION (§12.2 / §12.4)**:
  - **Idea 3**: *Airy Diffraction Specular Glint & Plateau-Border Capillary Rim Meniscus (`§12.2F Airy ring`)* — Replace the plain radial specular blob with a physical off-axis key-light reflection surrounded by an `airyDisc` diffraction ring (`§12.2F`) and a bright Plateau-border capillary drainage ring at `factor ≈ 0.94`.
  - **Idea 4**: *3-Wavelength Spherical Snell Vector Refraction (`§12.2F Snell vector refraction`)* — Construct the 3D spherical bubble normal `sphereN = vec3(direction * factor, cosInc)` and refract R, G, and B separately via `refract(vec3(0,0,-1), sphereN, 1.0 / iorRGB)` so the soap bubble exhibits true spherical chromatic dispersion at grazing incidence.

## 8. `gravitational-lensing` (`public/shaders/gravitational-lensing.wgsl`)
- **WHAT IS THIS**: 128-step Schwarzschild geodesic raytracer bending background texture rays around a central black hole and a secondary cursor gravity well, with a Shakura-Sunyaev Planck blackbody accretion disk, relativistic Doppler beaming (`dopplerFactor^3`), and 8-band FFT annuli.
- **MECHANISM INTERROGATION (§12.1)**:
  - *Primary mechanism*: Geodesic integration loop (`rayDir = normalize(rayDir + (accel + cursorAccel) * DT)`) tracking closest approach and sampling `readTexture` at `bgUV`, plus analytical `renderAccretionDisk`.
  - *Missing native detail*: Rays grazing the photon sphere (`r ≈ 1.5 * rs`) do not track their minimum periapsis `minR` or total azimuthal winding angle during the 128-step geodesic march, missing the sharp $n=1$ and $n=2$ lensed photon sub-rings, Lense–Thirring frame-dragging swirl, and Cauchy plasma dispersion near the horizon.
- **FORMULA ADMISSION (§12.2 / §12.4)**:
  - **Idea 3**: *Geodesic Periapsis $n=1$ / $n=2$ Photon Sub-Rings & Anisotropic Disk Corona Scattering (`§12.2F Henyey–Greenstein phase`)* — Track `minR` and total deflection angle `totalBend` inside the 128-step geodesic loop to ignite sharp $n=1$ (`minR ≈ 1.5 * rs`) and $n=2$ demagnified photon sub-rings weighted by forward Henyey–Greenstein coronal scattering (`hgPhase`).
  - **Idea 4**: *Cauchy Relativistic Plasma Dispersion & Lense-Thirring Frame-Dragging Twist (`§12.2F Cauchy dispersion`)* — Add Lense–Thirring azimuthal frame-dragging (`cross(vec3(0,1,0), toCenter)`) to the geodesic acceleration and sample the lensed background with 3-wavelength Cauchy plasma dispersion (`bgUV_R`, `bgUV_G`, `bgUV_B`) proportional to `totalBend`.

## 9. `spiral-lens` (`public/shaders/spiral-lens.wgsl`)
- **WHAT IS THIS**: Möbius-transformed kaleidoscopic spiral lens (`mobius`, `kaleido`) combining logarithmic and Archimedean spirals, FBM domain warping, barrel/pincushion lens distortion, chromatic aberration, and depth-of-field shading.
- **MECHANISM INTERROGATION (§12.1)**:
  - *Primary mechanism*: Complex Möbius map `mz = mobius(...)` folded by `kaleido(mz, segs)`, warped into `spiralAngle` and `lensedUV`, and sampled with R/G/B radial offsets.
  - *Missing native detail*: `kaleido` discards the sector fold index and mirror-seam distance (`seamDist`), so the kaleidoscopic mirror junctions have no physical beveled prism ridges, and the spiral arms shift UV directly rather than refracting through a 3D grooved Fresnel spiral lens normal via `refract()`.
- **FORMULA ADMISSION (§12.2 / §12.4)**:
  - **Idea 3**: *3D Grooved Spiral Fresnel-Zone Normals & Snell Vector Refraction (`§12.2F Snell vector refraction`)* — Construct a 3D surface normal `grooveNormal` from the spiral ridge phase (`spiralAngle`) and radial lens slope, refracting the view ray via 3D vector `refract(vec3(0,0,-1), grooveNormal, 1.0 / 1.52)` with grazing Fresnel specular glints along each spiral groove.
  - **Idea 4**: *Kaleidoscopic Sector Fold-Parity Tint & Mirror-Seam Bevel Glints (`§12.2E Fold count as material`)* — Compute the kaleidoscopic sector fold parity (`sectorParity`) and angular distance to the mirror fold plane (`seamDist`) so alternating sectors carry subtle complementary dichromatic tints and mirror seams gleam with beveled prism highlights.
