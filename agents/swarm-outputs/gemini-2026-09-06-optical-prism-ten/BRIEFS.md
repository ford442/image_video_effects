# Pre-Flight Idea Cards — Optical / Glass / Holographic / Prism (10 Shaders)
**Date:** 2026-09-06
**Cohort:** Gemini batch — optical / glass / holographic / prism (10)
**Contract Reference:** `docs/SHADER_UPGRADE_BATCH.md`

---

### 1. `chromatic-crawler-structure` (advanced-hybrid)
- **Current effect:** Color-swapping crawling infection guided by image structure tensor eigenvectors. Crawls along dominant orientations with filtered `textureSampleLevel(dataTextureC, ...)`.
- **Kept algorithms:** Structure tensor field ($J_{xx}, J_{yy}, J_{xy}$), eigenvalues, eigenvectors, coherency calculation, dominant orientation crawling, and palette LIC tinting.
- **Native visual ideas to add:**
  1. *Cauchy chromatic tendril bifurcation:* Wavelength-separated tendril propagation where R, G, B crawler offsets branch along orthogonal tensor eigenvectors with differential phase velocity.
  2. *Photoelastic fringe birefringence:* High-coherency edge stress regions produce multi-order chromatic retardation bands $\cos(\lambda_1 - \lambda_2)$.
  3. *Bioluminescent streamline pulse waves:* Audio bass and treble excite travelling photon pulse packets along crawling streamlines.
- **Floor hygiene:** Standard 7-line WGSL header; exact integer `textureLoad(dataTextureC, coord, 0)` feedback; ACES display RGBA; semantic alpha; pointer/click interaction; wire 3-band audio; byte-exact saved params with aligned `updatedParams`.
- **Springs:** Omitted (structure tensor flow field across image surface).

---

### 2. `chromatic-reaction-diffusion` (advanced-hybrid)
- **Current effect:** Multi-channel Gray-Scott reaction-diffusion with discrete 9-tap Laplacian; raw chemical states stored in `dataTextureA`.
- **Kept algorithms:** Multi-channel Gray-Scott PDE solver with separate feed/kill rates for R, G, B; 9-tap discrete Laplacian kernel; raw chemical state preservation in `dataTextureA` and `dataTextureC`.
- **Native visual ideas to add:**
  1. *Turing morphogen cross-gradient wave dispersion:* Morphogen gradients across channels couple to produce prismatic Turing wavebands at interface boundaries.
  2. *Interfacial Marangoni surface tension shear:* Interfacial chemical concentration differences generate micro-shear advection on optical background sampling.
  3. *Chemiluminescent boundary fluorescence:* Boundary edges fluoresce with wavelength-dependent emission proportional to reaction rate $\Delta C$.
- **Floor hygiene:** Standard 7-line WGSL header; clamped `textureLoad(dataTextureC, coord, 0)`; raw chemical state in `dataTextureA`; ACES tone mapping on display `writeTexture`; 3-band audio reactivity; held pointer drag + capped ripple wavefronts; byte-exact saved params with aligned `updatedParams`.
- **Springs:** Omitted (continuous spatial PDE domain).

---

### 3. `chroma-vortex-coupled` (advanced-hybrid)
- **Current effect:** Live fluid velocity advection and density field coupled to chromatic RGB swirl with mouse velocity stirring.
- **Kept algorithms:** Fluid state simulation in `dataTextureA` (velocity xy, vorticity, density) loaded from `dataTextureC`; semi-Lagrangian advection; mouse velocity vortex injection.
- **Native visual ideas to add:**
  1. *Cauchy prismatic dispersion streamline ribbons:* Vorticity curl ($\nabla \times \vec{v}$) dynamically shears R, G, B sampling angles into continuous spectral ribbons.
  2. *Acoustic vortex cavitation glints:* Low pressure core ($-\frac{1}{2}\rho |\vec{v}|^2$) triggers acoustic micro-cavitation flash glints modulated by treble.
  3. *Fluid rate-of-strain birefringence fringes:* Photoelastic retardation computed from the fluid symmetric rate-of-strain tensor $\frac{1}{2}(\nabla \vec{v} + \nabla \vec{v}^T)$.
- **Floor hygiene:** Standard 7-line WGSL header; bilinear manual interpolation over exact integer `textureLoad(dataTextureC)`; single-writer spring cursor in `extraBuffer[133..138]` for the vortex eye; ACES display; byte-exact saved params with aligned `updatedParams`.
- **Springs:** Single-writer spring in `extraBuffer[133..138]` at (0,0) tethered to the vortex eye mass.

---

### 4. `divine-light-gpt52` (lighting-effects)
- **Current effect:** Radial crepuscular ray marching toward center with Henyey-Greenstein phase function and dust motes; `dataTextureC` unused.
- **Kept algorithms:** Radial ray-marching with Henyey-Greenstein phase function, warped FBM dust motes, Voronoi cellular motes, and center bloom.
- **Native visual ideas to add:**
  1. *Cauchy spectral dispersion along crepuscular rays:* Wavelength-dependent radial raymarching creates chromatic rainbow rims along light beam margins.
  2. *Cathedral rose-window stained-glass chromatic projection:* Analytic kaleidoscopic stained-glass modulation across radial beam angles.
  3. *Airy disk multi-ring diffraction halo:* Concentric chromatic Airy diffraction rings surrounding the divine emitter.
- **Floor hygiene:** Standard 7-line WGSL header; exact `textureLoad(dataTextureC, coord, 0)` for atmospheric beam phosphor persistence; single-writer spring in `extraBuffer[133..138]` for light source inertia; ACES tone-mapping; byte-exact saved params with aligned `updatedParams`.
- **Springs:** Single-writer spring in `extraBuffer[133..138]` at (0,0) tethered to the emitter position.

---

### 5. `aurora-rift-pass1` (lighting-effects)
- **Current effect:** Volumetric curl-noise aurora raymarch pass 1; packs volumetric color & density into `dataTextureA` for pass 2 compositor; `zoom_params.z` dead slider; out-of-bounds guard missing.
- **Kept algorithms:** Multi-layer depth-parallax curl-noise flow field, 4D hyper-noise, Voronoi cellular foam, and volumetric density handoff to Pass 2 in `dataTextureA`.
- **Native visual ideas to add:**
  1. *Geomagnetic Birkeland current vertical curtain folds:* Vertical magnetic striations with altitude-dependent pitch and curtain flutter.
  2. *Atmospheric discrete spectral emission physics:* Realistic altitude emission bands (557.7nm green oxygen base, 630.0nm red oxygen crown, 427.8nm blue nitrogen fringe).
  3. *Diffusion-rate driven temporal ribbon drift:* Connect `zoom_params.z` (`diffRate`) to active temporal diffusion and advection from `dataTextureC`.
- **Floor hygiene:** Standard 7-line WGSL header; out-of-bounds guard; exact `textureLoad(dataTextureC)` for ribbon persistence; wire all 4 sliders live; byte-exact saved params with aligned `updatedParams`.
- **Springs:** Omitted (large-scale atmospheric curtain).

---

### 6. `aurora-rift-2-pass1` (lighting-effects)
- **Current effect:** Enhanced volumetric raymarch pass 1; packs volumetric color & density into `dataTextureA`; `zoom_params.z` dead slider; out-of-bounds guard missing.
- **Kept algorithms:** Enhanced 3-layer parallax curl-noise field, 4D noise, phase-interference wavefronts, density handoff to Pass 2.
- **Native visual ideas to add:**
  1. *Birkeland current plasma vortex tubes:* Paired counter-rotating magnetic vortex sheaths along the auroral ribbons.
  2. *Ionospheric geomagnetic substorm flash:* Treble and click ripples trigger substorm bursts with violet $N_2^+$ boundary glow.
  3. *Multi-scale layer diffusion coupling:* Real cross-layer diffusion advection driven by `zoom_params.z` (`diffRate`).
- **Floor hygiene:** Standard 7-line WGSL header; out-of-bounds guard; exact `textureLoad(dataTextureC)` persistence; 4 sliders live; byte-exact saved params with aligned `updatedParams`.
- **Springs:** Omitted (large-scale atmospheric curtain).

---

### 7. `gen-chromatic-glass-lattice` (generative)
- **Current effect:** Raymarched 3D glass lattice (box + octahedron KIFS repetition) with mouse shatter; filtered `textureSampleLevel` on C; hardcoded `etaBase = 1.5` ignoring `zoom_params.x`.
- **Kept algorithms:** Repetitive octahedral-box glass lattice SDF, domain repetition, core glow sphere, mouse shatter voronoi dynamics.
- **Native visual ideas to add:**
  1. *Cauchy multi-order dispersion with internal TIR caustic ribs:* True wavelength-dependent refractive indices from live `zoom_params.x` (`refraction_index`) with internal total reflection caustics.
  2. *Acoustic resonance stress birefringence:* Audio bass/mids induce dynamic stress tensor fields inside the glass struts, producing photoelastic isochromatic fringes.
  3. *Micro-fracture edge sparkle glints:* Grazing-angle facet glints along shattered lattice edges with chromatic flare.
- **Floor hygiene:** Standard 7-line WGSL header; exact `textureLoad(dataTextureC)`; single-writer spring cursor in `extraBuffer[133..138]` for shatter impact mass; ACES tone-mapping; pass `refractionIdx` to `etaBase`; byte-exact saved params with aligned `updatedParams`.
- **Springs:** Single-writer spring in `extraBuffer[133..138]` at (0,0) tethered to shatter impact center.

---

### 8. `gen-celestial-prism-orchid` (generative)
- **Current effect:** Raymarched organic floral crystalline KIFS with cosmic wind FBM and pollinator mouse wind; Reinhard tonemap.
- **Kept algorithms:** 5-iteration KIFS floral petal folding, starlight core SDF, cosmic wind FBM, pollinator mouse wind, click petal ripples.
- **Native visual ideas to add:**
  1. *Cauchy prismatic petal-edge dispersion:* Multi-spectral dispersion through thin-edged petal bevels with Rayleigh volume scattering.
  2. *Micro-venation bioluminescent nutrient flow:* Pulsing nutrient and photonic currents along petal capsule veins synchronized with audio treble/bass.
  3. *Starlight corona diffraction starburst:* Multi-armed anamorphic diffraction starburst with thin-film interference surrounding the core.
- **Floor hygiene:** Standard 7-line WGSL header; exact `textureLoad(dataTextureC)`; single-writer spring cursor in `extraBuffer[133..138]` for pollinator mass; ACES display; byte-exact saved params with aligned `updatedParams`.
- **Springs:** Single-writer spring in `extraBuffer[133..138]` at (0,0) for pollinator creature position.

---

### 9. `gen-celestial-quantum-glass-dragonfly` (generative)
- **Current effect:** Biomechanical quantum-glass dragonfly raymarch; misses `dataTextureA` write; reads `readTexture` instead of `dataTextureC`; depth is 0; audio is scalar from config.y.
- **Kept algorithms:** Dragonfly SDF (segmented tail, head, thorax, flapping fractal venation wings), volumetric background plasma storm.
- **Native visual ideas to add:**
  1. *Cauchy thin-film dragonfly wing iridescence:* Multi-order chromatic thin-film interference fringes with angle-of-incidence color shift across fractal wing membranes.
  2. *Quantum glass internal caustic core & photon emission:* Refractive starlight light-piping through segmented crystalline abdomen and compound eyes.
  3. *Acoustic wing-tip vortex trails:* Wingtips shed glowing aerodynamic vortices into plasma storm synchronized with audio bass/treble wingbeats.
- **Floor hygiene:** Standard 7-line WGSL header; exact `textureLoad(dataTextureC)` history; single-writer spring in `extraBuffer[133..138]` for dragonfly flight agility; real normalized depth output; ACES display; wire `plasmaBuffer[0].xyz`; byte-exact saved params with aligned `updatedParams`.
- **Springs:** Single-writer spring in `extraBuffer[133..138]` at (0,0) for dragonfly position.

---

### 10. `gen-celestial-glass-tornado` (generative)
- **Current effect:** Raymarched celestial glass tornado with KIFS debris, spring cursor in `extraBuffer[133..138]`, click glass rings. Glass shading is basic proximity reciprocal.
- **Kept algorithms:** Tornado vortex SDF, KIFS crystalline debris, single-writer spring cursor in `extraBuffer[133..138]`, click glass rings, ACES display.
- **Native visual ideas to add:**
  1. *Cauchy prismatic glass facet TIR glints:* Analytic normal calculation on tornado and KIFS debris, Fresnel reflection, and Cauchy spectral dispersion across rotating crystal faces.
  2. *Helical plasma funnel discharge arcs:* Helical lightning arcs spiraling down tornado's inner vortex core driven by audio bass and mids.
  3. *Centrifugal glass dust accretion disk:* Spinning equatorial accretion sheet of pulverized crystal micro-particles scattering ambient starlight.
- **Floor hygiene:** Standard 7-line WGSL header; exact `textureLoad(dataTextureC)`; preserve existing single-writer spring in `extraBuffer[133..138]`; ACES display; byte-exact saved params with aligned `updatedParams`.
- **Springs:** Single-writer spring in `extraBuffer[133..138]` at (0,0) preserved.
