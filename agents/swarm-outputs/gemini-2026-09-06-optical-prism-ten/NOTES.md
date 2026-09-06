# Implementation Notes — Optical / Glass / Holographic / Prism (10 Shaders)
**Date:** 2026-09-06
**Batch:** Gemini batch — optical / glass / holographic / prism (10)
**Contract Reference:** `docs/SHADER_UPGRADE_BATCH.md`

---

### 1. `chromatic-crawler-structure` (advanced-hybrid)
- **Kept Algorithms:** Structure tensor smoothing ($J_{xx}, J_{yy}, J_{xy}$), trace/det/difference eigenvalue solver ($\lambda_1, \lambda_2$), eigenvector normalization, coherency metric, discrete hash-based channel swaps, palette LIC color mapping.
- **A / C State Packing:** Display RGBA stored in `dataTextureA` with exact-integer `textureLoad(dataTextureC, coord, 0)` previous-frame persistence. Semantic alpha packs coherency confidence.
- **Native Visual Additions in Diff:**
  1. *Cauchy chromatic tendril bifurcation:* Wavelength-separated tendril propagation branching R, G, B offsets along orthogonal eigenvectors.
  2. *Photoelastic fringe birefringence:* High-coherency edge stress regions produce multi-order chromatic retardation bands $\cos(\lambda_1 - \lambda_2)$.
  3. *Bioluminescent streamline pulse waves:* Audio bass and treble excite travelling photon pulse packets along crawling streamlines.

---

### 2. `chromatic-reaction-diffusion` (advanced-hybrid)
- **Kept Algorithms:** Multi-channel Gray-Scott PDE system with distinct feed/kill rates for R, G, B; 9-tap discrete Laplacian kernel; background channel-separation displacement.
- **A / C State Packing:** Raw simulation state `vec4<f32>(newR, newG, newB, activity)` in `dataTextureA`; exact integer loads from `dataTextureC`; ACES display output to `writeTexture`.
- **Native Visual Additions in Diff:**
  1. *Turing morphogen cross-gradient wave dispersion:* Cross-channel chemical gradients couple to produce anisotropic wavebands.
  2. *Interfacial Marangoni surface tension shear:* High chemical concentration differences generate micro-shear advection on optical background sampling.
  3. *Chemiluminescent boundary fluorescence:* Sharp chemical boundaries fluoresce with wavelength-dependent emission proportional to reaction rate.

---

### 3. `chroma-vortex-coupled` (advanced-hybrid)
- **Kept Algorithms:** Navier-Stokes fluid velocity advection and density transport in `dataTextureA` and `dataTextureC`; semi-Lagrangian advection; mouse velocity vortex injection; chromatic angle swirl.
- **A / C State Packing:** Physical fluid state `vec4<f32>(vel.x, vel.y, vorticity, dens)` in `dataTextureA`; bilinear manual interpolation over exact integer `textureLoad(dataTextureC)`.
- **Native Visual Additions in Diff:**
  1. *Cauchy prismatic dispersion streamline ribbons:* Vorticity curl ($\nabla \times \vec{v}$) dynamically shears R, G, B sampling angles into continuous spectral ribbons.
  2. *Acoustic vortex cavitation glints:* Low pressure vortex eye triggers acoustic micro-cavitation flash glints modulated by treble.
  3. *Fluid rate-of-strain birefringence fringes:* Photoelastic retardation computed from the fluid symmetric rate-of-strain tensor $\frac{1}{2}(\nabla \vec{v} + \nabla \vec{v}^T)$.

---

### 4. `divine-light-gpt52` (lighting-effects)
- **Kept Algorithms:** Radial raymarching toward emitter; Henyey-Greenstein volumetric phase function; warped FBM and Voronoi cellular dust motes; emitter bloom halo.
- **A / C State Packing:** Display RGBA stored in `dataTextureA`; exact `textureLoad(dataTextureC, coord, 0)` for atmospheric beam phosphor persistence.
- **Native Visual Additions in Diff:**
  1. *Cauchy spectral dispersion along crepuscular rays:* Differential radial sampling offsets for R, G, B creating rainbow chromatic fringes.
  2. *Cathedral rose-window stained-glass chromatic projection:* Analytic kaleidoscopic stained-glass modulation across radial beam angles.
  3. *Airy disk multi-ring diffraction halo:* Concentric chromatic Airy diffraction rings surrounding the divine emitter.

---

### 5. `aurora-rift-pass1` (lighting-effects)
- **Kept Algorithms:** Multi-layer depth-parallax curl-noise flow field; 4D hyper-noise; Voronoi cellular foam; volumetric density handoff to Pass 2 in `dataTextureA`.
- **A / C State Packing:** Volumetric handoff `vec4<f32>(ditheredColor, density)` in `dataTextureA`; exact `textureLoad(dataTextureC, coord, 0)` for ribbon persistence.
- **Native Visual Additions in Diff:**
  1. *Geomagnetic Birkeland current vertical curtain folds:* Vertical magnetic striations with altitude-dependent pitch and curtain flutter.
  2. *Atmospheric discrete spectral emission physics:* Realistic altitude emission bands (557.7nm green oxygen base, 630.0nm red oxygen crown, 427.8nm blue nitrogen fringe).
  3. *Diffusion-rate driven temporal ribbon drift:* Wired `zoom_params.z` (`diffRate`) to active temporal diffusion and advection from `dataTextureC`.

---

### 6. `aurora-rift-2-pass1` (lighting-effects)
- **Kept Algorithms:** Enhanced 3-layer parallax curl-noise field; 4D noise; phase-interference wavefronts; density handoff to Pass 2 in `dataTextureA`.
- **A / C State Packing:** Volumetric handoff `vec4<f32>(ditheredColor, density)` in `dataTextureA`; exact `textureLoad(dataTextureC, coord, 0)` for ribbon persistence.
- **Native Visual Additions in Diff:**
  1. *Birkeland current plasma vortex tubes:* Paired magnetic vortex sheaths along auroral ribbons with high-speed helical spinning.
  2. *Ionospheric geomagnetic substorm flash bursts:* Treble and click ripples trigger substorm bursts with violet $N_2^+$ boundary glow.
  3. *Multi-scale layer diffusion coupling:* Cross-layer diffusion advection driven by live `zoom_params.z` (`diffRate`).

---

### 7. `gen-chromatic-glass-lattice` (generative)
- **Kept Algorithms:** 3D raymarching of octahedral-box glass lattice SDF; domain repetition; core glow sphere; mouse shatter voronoi dynamics.
- **A / C State Packing:** Display RGBA stored in `dataTextureA`; exact `textureLoad(dataTextureC, coord, 0)` previous-frame persistence.
- **Native Visual Additions in Diff:**
  1. *Cauchy multi-order dispersion with internal TIR caustic ribs:* True wavelength-dependent refractive indices from live `zoom_params.x` (`refraction_index`) with internal total reflection caustics.
  2. *Acoustic resonance stress birefringence:* Audio bass/mids induce dynamic stress tensor fields inside the glass struts, producing photoelastic isochromatic fringes.
  3. *Micro-fracture edge sparkle glints:* Grazing-angle facet glints along shattered lattice edges with chromatic flare.

---

### 8. `gen-celestial-prism-orchid` (generative)
- **Kept Algorithms:** 5-iteration KIFS floral petal folding; starlight core SDF; cosmic wind FBM; pollinator mouse wind; click petal ripples.
- **A / C State Packing:** Display RGBA stored in `dataTextureA`; exact `textureLoad(dataTextureC, coord, 0)` previous-frame persistence; normalized depth output.
- **Native Visual Additions in Diff:**
  1. *Cauchy prismatic petal-edge dispersion:* Multi-spectral Cauchy dispersion indices through thin-edged petal bevels with Rayleigh volume scattering.
  2. *Micro-venation bioluminescent nutrient flow:* Pulsing nutrient and photonic currents along petal capsule veins synchronized with audio treble/bass.
  3. *Starlight corona diffraction starburst:* Multi-armed anamorphic diffraction starburst with thin-film interference surrounding the core.

---

### 9. `gen-celestial-quantum-glass-dragonfly` (generative)
- **Kept Algorithms:** Dragonfly SDF (segmented tail, head, thorax, flapping fractal venation wings); volumetric background plasma storm.
- **A / C State Packing:** Display RGBA stored in `dataTextureA`; exact `textureLoad(dataTextureC, coord, 0)` history; real normalized depth output.
- **Native Visual Additions in Diff:**
  1. *Cauchy thin-film dragonfly wing iridescence:* Multi-order chromatic thin-film interference fringes with angle-of-incidence color shift across fractal wing membranes.
  2. *Quantum glass internal caustic core & photon emission:* Refractive starlight light-piping through segmented crystalline abdomen and compound eyes.
  3. *Acoustic wing-tip vortex trails:* Wingtips shed glowing aerodynamic vortices into plasma storm synchronized with audio bass/treble wingbeats.

---

### 10. `gen-celestial-glass-tornado` (generative)
- **Kept Algorithms:** Tornado vortex SDF; KIFS crystalline debris; single-writer spring cursor in `extraBuffer[133..138]`; click glass rings; ACES display.
- **A / C State Packing:** Display RGBA stored in `dataTextureA`; exact `textureLoad(dataTextureC, coord, 0)` previous-frame persistence.
- **Native Visual Additions in Diff:**
  1. *Cauchy prismatic glass facet TIR glints:* Analytic normal calculation on tornado and KIFS debris, Fresnel reflection, and Cauchy spectral dispersion across rotating crystal faces.
  2. *Helical plasma funnel discharge arcs:* Helical lightning arcs spiraling down tornado's inner vortex core driven by audio bass and mids.
  3. *Centrifugal glass dust accretion disk:* Spinning equatorial accretion sheet of pulverized crystal micro-particles scattering ambient starlight.
