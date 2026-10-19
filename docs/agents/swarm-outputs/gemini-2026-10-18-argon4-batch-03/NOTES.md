# Gemini Argon4 (`argon4/batch-03`) — Implementation Notes

Batch date: `2026-10-18`

## Prelude Migration (Infrastructure Only)
Ran `python3 scripts/migrate_to_prelude.py --files ...` prior to WGSL edits on the 7 files that still pasted the 13 bindings:
- `public/shaders/gen-prismatic-quantum-fractal-nautilus-engine.wgsl`
- `public/shaders/glass-refraction-prismatic.wgsl`
- `public/shaders/anamorphic-flare-iridescence.wgsl`
- `public/shaders/crystal-illuminator-iridescence.wgsl`
- `public/shaders/holographic-interferometry-bilateral.wgsl`
- `public/shaders/frosted-glass-lens-iridescence.wgsl`
- `public/shaders/dynamic-lens-flares-prismatic.wgsl`

(`gen-prismatic-cyber-chrono-nebula-peacock.wgsl`, `gen-celestial-quantum-glass-dragonfly.wgsl`, and `gen-ethereal-quantum-holographic-fractal-coral.wgsl` already used `#include "_prelude.wgsl"`.)

---

## Per-Shader Verification & Diff Map

### 1. `gen-prismatic-cyber-chrono-nebula-peacock`
- **Kept verbatim:** Quantum glass body + KIFS folded feather train (`featherFold`), barbule thin-film interference (`barbuleThinFilm`), zoned ocellus eye-spots (`ocellusZones`), rachis-barb shafts (`rachisBarbs`), precessing ocellus halo (`ocellusHalo`), and click-ripple train rattle (`shiver`).
- **A packing:** `A = ACES display RGBA`.
- **Ideas visible in diff:**
  1. `sdCrestAigrettes` (`mat == 2.0`, `aigretteCol`) — 7-quill coronet crest fan atop the head with turquoise-gold spatula bulbs.
  2. `braggRodLattice` & `chronoAfterimage` — 2D melanin photonic-crystal rod-lattice Bragg shift across barbule tilt angle + `dataTextureC` chrono-afterimage persistence + upright `uv.y` orientation fix.
- **Sliders:** `zoom_params.x..w` (`Plumage Spread`, `Quantum Glass Refraction`, `Nebula Density`, `Audio Reactivity`) unchanged.

### 2. `gen-prismatic-quantum-fractal-nautilus-engine`
- **Kept verbatim:** Logarithmic spiral shell (`spiralMap`), fractal inner chambers (`chamberDist`), mechanical greebles, auroral plasma core, view-angle cosine iridescence, subsurface spectral dispersion (`sssCol`), `fbm3` internal energy veins, and `extraBuffer[0]` bass envelope.
- **A packing:** `A = ACES display RGBA`.
- **Ideas visible in diff:**
  1. `septaWall` & `siphuncleTube` (`mat == 2.0`, `siphuncleGlow`) — concave calcified septa chamber bulkheads and central pressurized siphuncle osmotic conduit threading the spiral chambers.
  2. `nacreBrickStack` & `tigerStripeMask` (`tigerFlame`, `septaCrest`) — ~500 nm aragonite nacre platelet Bragg interference and outer-whorl *Nautilus* periostracum tiger-stripe flame banding.
- **Sliders:** `zoom_params.x..w` (`Aura Intensity`, `Spiral Expansion`, `Fractal Depth`, `Audio Reactivity`) unchanged.

### 3. `gen-celestial-quantum-glass-dragonfly`
- **Kept verbatim:** Forewing/hindwing KIFS venation + trailing-edge vortex flutter (`mapWings`), thorax/head/segmented tail (`mapBody`), `extraBuffer[133..138]` spring-damper flight + velocity banking, Cauchy 3-band wing refraction + thin-film, hexagonal compound eye lattice, and tail quantum decoherence static.
- **A packing:** `A = ACES display RGBA (semantic wing/body alpha)`.
- **Ideas visible in diff:**
  1. `pterostigmaBulge`, `nodusPinch`, `pterostigmaMask`, `nodusCrease`, `pterostigmaGlow` — dense amber-refractive leading-edge pterostigma wingtip counterweight cell and mid-wing nodus torsion hinge.
  2. `wingPhaseLag` (`1.5707963`), `ocelliTriad`, `thoraxMuscleFibers` — 90-degree biomechanical counter-stroking phase offset between forewings and hindwings, plus 3 dorsal simple ocelli on the head vertex and oblique flight-muscle myofibril bands in the glass thorax.
- **Sliders:** `zoom_params.x..w` (`Wing Frequency`, `Fractal Density`, `Refraction Index`, `Glow Intensity`) unchanged.

### 4. `gen-ethereal-quantum-holographic-fractal-coral`
- **Kept verbatim:** KIFS fractal coral branches (`map`) with Voronoi organic noise, polyp mouth pits (`pitSDF`), swaying 3-stalk polyp tentacle tufts (`gTuft`), bass spawning bursts (`gBurst`), and zooxanthellae green breathing pulse from `dataTextureC`.
- **A packing:** `A = ACES display RGBA (alpha = branch coverage)`.
- **Ideas visible in diff:**
  1. `scleroseptaRidges`, `growthAnnuli`, `gCoralliteRim`, `gGrowthBand` — 12-fold radial calcareous septa blades around each corallite cup and concentric aragonite skeletal growth-ring bands.
  2. `fretEmission` (`gfpDonor`, `rfpAcceptor`) & `seawaterCaustics` — mesenterial filament GFP/RFP donor-acceptor FRET fluorescence along polyp rims and overhead marine surface Voronoi caustics.
- **Sliders:** `zoom_params.x..w` (`Fractal Density`, `Holographic Frequency`, `Bio-Luminescence Intensity`, `Audio Pulse Propagation`) unchanged.

### 5. `glass-refraction-prismatic`
- **Kept verbatim:** Raymarched 3-sphere + ribbon `smoothUnion` glass SDF (`map`), 4-band Cauchy dispersion (`450..680 nm`), Fresnel dielectric reflection, Beer-Lambert absorption, internal edge glow, and `extraBuffer[133..138]` pointer spring.
- **A packing:** `A = ACES display RGBA`.
- **Ideas visible in diff:**
  1. `pExit`, `exitNormal`, `refracted2`, `tirFire` — interior raymarch to back-face exit interface for two-surface Snell refraction and critical-angle total-internal-reflection prismatic fire.
  2. `curvatureFocus` & `brewsterGlint` — front/back curvature caustic convergence and Brewster-angle s/p polarized rim highlight.
- **Sliders:** `zoom_params.x..w` (`Transparency`, `Cauchy B Coefficient`, `Thickness Scale`, `Surface Roughness`) unchanged.

### 6. `anamorphic-flare-iridescence`
- **Kept verbatim:** Horizontal/vertical `anamorphicStreak`, hexagonal `ghostElement` train, `centralGlow`, 6-point `starburst`, rainbow halo ring, `thinFilmColor` interference, and `extraBuffer[133..138]` light spring.
- **A packing:** `A = ACES display RGBA`.
- **Ideas visible in diff:**
  1. `anamorphicOvalBokeh`, `catsEyeClip`, `arCoatingTint` — 2:1 cylindrical anamorphic squeeze oval bokeh ghosts with peripheral cat's-eye mechanical vignetting and quarter-wave MgF2/TiO2 AR coating tints.
  2. `streakDiffractionComb`, `dualRail`, `sensorGridGlint` — horizontal Fraunhofer diffraction micro-comb along the anamorphic streak and CMOS sensor microlens cross-grid glints.
- **Sliders:** `zoom_params.x..w` (`Flare Intensity`, `Streak Length`, `Film Thickness`, `Film IOR`) unchanged.

### 7. `crystal-illuminator-iridescence`
- **Kept verbatim:** 2D Voronoi crystal facets (`min_dist`, `second_min_dist`, `cell_id`), per-cell facet normal + dome curvature, `extraBuffer[133..138]` spring cursor lamp, Fresnel IOR, per-facet `thinFilmColor`, click ripples, and Beer-Lambert transmission alpha.
- **A packing:** `A = ACES display RGBA`.
- **Ideas visible in diff:**
  1. `opticAxis`, `cleavageStep`, `birefringentSplit`, `read_uv_o`, `read_uv_e`, `malusWeight` — per-grain crystal optic axis splitting ordinary and extraordinary refracted rays with rhombohedral cleavage growth steps.
  2. `internalFacetBounce` & `inclusionGlint` — sub-facet internal reflection bounce off steep inter-grain boundaries and microscopic trapped fluid-inclusion sparkles.
- **Sliders:** `zoom_params.x..w` (`Cell Density`, `IOR Mix`, `Light Power`, `Film Thickness`) unchanged.

### 8. `holographic-interferometry-bilateral`
- **Kept verbatim:** Object + reference wave `interferencePattern`, `spectralReconstruct` rainbow, `speckleNoise`, 5×5 edge-preserving bilateral filter (`smoothedHolo`, `edgeConfidence`), parallax depth view offset, and `extraBuffer[133..138]` spring cursor.
- **A packing:** `A = ACES display RGBA`.
- **Ideas visible in diff:**
  1. `strainPhaseDelta` & `moireBeatFringe` — double-exposure holographic strain interferometry beat fringes mapping iso-deformation contours.
  2. `opticalVortexPhase` (`forkDislocation`) & `braggEnvelope` — topological charge $m=\pm 1$ phase-singularity fork dislocations in the reference carrier and Lippmann-Bragg $\text{sinc}^2$ volume-grating wavelength selectivity.
- **Sliders:** `zoom_params.x..w` (`Fringe Density`, `Coherence Length`, `Reconstruction Angle`, `Color Saturation`) unchanged.

### 9. `frosted-glass-lens-iridescence`
- **Kept verbatim:** Magnifying lens around `smoothMouse` (`lensRadius`, `edgeSoftness`), pointer-drag moisture wipe (`wipeFactor`), microscopic condensation droplet beads (`dropMask`), Beer-Lambert glass absorption, `thinFilmColor` coating, and lens bevel Cauchy dispersion.
- **A packing:** `A = ACES display RGBA`.
- **Ideas visible in diff:**
  1. `iceFernCrystal`, `frostNormal`, `poissonScatter` — anisotropic 6-fold dendritic ice-fern crystal needles and 6-tap golden-angle Poisson microfacet scattering.
  2. `wipeMeniscusBead` (`meniscusRefract`) & `newtonRingPhase` — plowed capillary condensation meniscus ridge along the wiped rim and concentric plano-convex Newton's-ring air-gap interference inside the lens.
- **Sliders:** `zoom_params.x..w` (`Frost Amount`, `Lens Radius`, `Edge Softness`, `Film IOR`) unchanged.

### 10. `dynamic-lens-flares-prismatic`
- **Kept verbatim:** Multi-ghost optical train (`i < maxGhosts`) along `center - smoothLight` axis, 4-band Cauchy dispersion (`refractThroughSurface`), halo ring, 12-ray starburst, `readTexture` thresholded source color, and `extraBuffer[133..138]` light spring.
- **A packing:** `A = ACES display RGBA`.
- **Ideas visible in diff:**
  1. `irisPolygonGhost` (`comaStretch`, `fresnelRimRing`) — 7-blade heptagonal iris diaphragm ghosts with Fresnel edge-diffraction ringing and off-axis Petzval coma stretch.
  2. `ciliaryNeedles` & `chromaticCorona` — wavelength-scaled Fraunhofer radial diffraction needle corona (`450..680 nm`).
- **Sliders:** `zoom_params.x..w` (`Intensity`, `Threshold`, `Spread`, `Ghost Count`) unchanged.
