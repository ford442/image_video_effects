# Chromatic/RGB Shader Upgrade Plan

## Executive Summary

This document outlines artistic and computational upgrade opportunities for 22 chromatic/RGB shaders in the Pixelocity WebGPU project. Each shader is analyzed for its current capabilities and paired with scientifically-grounded visual enhancements based on real-world optical phenomena.

---

## Scientific Concepts Reference

| Concept | Description | Visual Signature |
|---------|-------------|------------------|
| **Chromatic Aberration** | Wavelength-dependent refraction | Red/blue fringing at high-contrast edges |
| **Prism Dispersion (Cauchy)** | n(λ) = A + B/λ² | Rainbow spectrum spread, non-linear separation |
| **Thin-Film Interference** | Phase-shifted wave reflection | Iridescent color shifts (oil slick, soap bubbles) |
| **Birefringence** | Double refraction in anisotropic materials | Duplicate ghost images with perpendicular polarization |
| **Dichroic Filters** | Wavelength-selective reflection/transmission | Sharp color separation at specific angles |
| **Spectral Power Distribution** | Energy distribution across wavelengths | Realistic color temperature shifts |
| **CIE Color Space** | Device-independent color representation | Perceptually uniform color interpolation |
| **Metamerism** | Different spectra, same perceived color | Context-dependent color matching |
| **Rayleigh Scattering** | λ⁻⁴ scattering dependence | Blue-shifted atmospheric haze |
| **Grating Diffraction** | Constructive interference at angles | Ordered spectral lines, rainbow orders |

---

## Shader Analysis & Upgrade Plans

### 1. chromatic-shockwave (2,789 bytes)

**Current Visual Description:**
Radial shockwave emanating from mouse position with simple RGB directional offsets. Uses sine wave modulation based on distance from mouse, with red channel displaced outward, blue inward, and green at reduced amplitude.

**Current Technique:**
- Radial distance-based wave function: `sin(dist * freq - time * speed)`
- Directional chromatic separation along radius vector
- Static RGB offset weights (R=1.0, G=0.3, B=-1.0)

**Artistic Upgrade Concept:**
**"Prismatic Shockwave"** - Transform the simple RGB split into a physically accurate dispersion simulation based on Cauchy's equation. The shockwave becomes a traveling rainbow spectrum with wavelength-dependent propagation speeds, mimicking a lightning strike through a prism.

**Computational Technique to Add:**
- Implement Cauchy's dispersion equation: n(λ) = A + B/λ²
- Sample 7 spectral bands (red through violet) instead of 3 RGB channels
- Apply velocity dispersion: shorter wavelengths travel faster through the "medium"
- Add secondary shockwave (rarefaction following compression) with inverted dispersion

**Visual Reference:**
Lightning strike viewed through a prism—primary bright white-blue flash followed by radially-expanding color rings that separate based on wavelength, with violet leading and red trailing. The dispersion increases with distance from center.

**Implementation Complexity:** Medium
- 7 texture samples per pixel (vs current 3)
- Requires spectral-to-RGB conversion function
- Additional uniform for dispersion coefficient

**Dependencies:**
- None beyond existing bindings

---

### 2. chroma-shift-grid (2,793 bytes)

**Current Visual Description:**
Grid-based chromatic displacement where each cell applies uniform directional RGB shifts based on distance from mouse. Grid overlay provides visual structure.

**Current Technique:**
- Grid quantization: `floor(uv * gridSize)`
- Uniform per-cell chromatic offset
- Directional shift with configurable angle

**Artistic Upgrade Concept:**
**"Dichroic Grid Matrix"** - Transform into a dynamic dichroic filter array where each grid cell acts as a micro-prism with angle-dependent color separation. The grid becomes a field of tiny interference filters.

**Computational Technique to Add:**
- Implement Bragg reflection interference: wavelength-dependent transmission angles
- Per-cell orientation based on grid position + time
- Simulate thin-film stack: `T(λ,θ) = 4n₁n₂/(n₁+n₂)² × interference_term`
- Add polarization-aware dual images (birefringence effect)

**Visual Reference:**
Security hologram or dichroic glass artwork—each grid square displays different colors depending on viewing angle, with smooth transitions between cells creating a rippling chromatic field.

**Implementation Complexity:** High
- Per-cell angular calculation
- Multiple interference calculations per pixel
- Requires phase accumulation across virtual film layers

**Dependencies:**
- Additional noise texture for film thickness variation (could use hash function)

---

### 3. chromatic-focus (2,850 bytes)

**Current Visual Description:**
Mouse-centered depth-of-field with chromatic aberration increasing radially from focus point. Clean, sharp focus at mouse position with gradual RGB separation toward edges.

**Current Technique:**
- `smoothstep` falloff from focus radius
- Radial directional offset for R/B channels
- Configurable aberration strength and focus radius

**Artistic Upgrade Concept:**
**"Achromatic Doublet Lens Simulation"** - Upgrade to simulate real camera lens aberrations including spherical aberration, coma, and longitudinal chromatic aberration. The focus becomes a physical lens model with configurable glass types.

**Computational Technique to Add:**
- Implement Seidel aberration coefficients
- Model longitudinal chromatic aberration (axial color separation)
- Add spherical aberration: rays at edge focus at different point than center
- Simulate lens flare/ghosting from internal reflections

**Visual Reference:**
Vintage Petzval lens photograph—dreamy swirl bokeh with purple/green fringing at specular highlights, soft glow around bright objects, characteristic "soap bubble" bokeh balls.

**Implementation Complexity:** High
- Multiple sample points per pixel for bokeh simulation
- Requires convolution approximation for lens PSF
- Complex aberration polynomial evaluation

**Dependencies:**
- dataTextureB for lens flare accumulation

---

### 4. rgb-ripple-distortion (2,854 bytes)

**Current Visual Description:**
Wave-based RGB channel displacement with phase-shifted sinusoids for each channel. Creates interference pattern appearance with concentric color rings.

**Current Technique:**
- Phase-shifted sine waves per channel: `sin(phase + channel_offset)`
- Exponential decay from mouse: `exp(-dist * 3.0)`
- Directional displacement along radius vector

**Artistic Upgrade Concept:**
**"Surface Acoustic Wave Diffraction"** - Transform into simulation of photoelastic stress patterns where RGB channels represent different polarization states interacting with stressed material.

**Computational Technique to Add:**
- Implement photoelasticity: stress-induced birefringence
- Model stress distribution from wave propagation
- Add polarization rotation: `I = I₀cos²(φ)` where φ is retardation angle
- Simulate isochromatic fringe patterns (order-based color bands)

**Visual Reference:**
Photoelastic stress analysis image—rainbow interference fringes revealing internal stress patterns, sharp transitions between color orders, black isoclinic lines showing principal stress directions.

**Implementation Complexity:** Medium-High
- Requires stress field computation
- Polarization mathematics
- Color-to-fringe-order mapping

**Dependencies:**
- dataTextureA for stress field accumulation

---

### 5. rgb-iso-lines (2,960 bytes)

**Current Visual Description:**
Contour lines extracted from each RGB channel separately, creating technical/topographic visualization aesthetic. Lines follow luminance/value contours with parallax offset.

**Current Technique:**
- Per-channel contour extraction: `fract(value * freq) - 0.5`
- smoothstep-based line width control
- Mouse-based parallax offset per channel

**Artistic Upgrade Concept:**
**"Hyperspectral Topographic Map"** - Upgrade to full spectral analysis visualization where iso-lines represent equal-energy surfaces across continuous spectrum, with CIE color space warping.

**Computational Technique to Add:**
- Sample full spectrum via multiple wavelengths
- Map to CIE XYZ color space with proper chromatic adaptation
- Add spectral gradient flow visualization (streamlines)
- Implement metamerism detection: highlight colors with same appearance but different spectra

**Visual Reference:**
NASA hyperspectral imaging data visualization—dense contour networks with scientifically accurate color gradations, flow arrows showing spectral gradients, highlighted "metamer regions" where different spectra converge.

**Implementation Complexity:** Very High
- Requires 7+ samples for spectrum approximation
- CIE color space transformation matrices
- Streamline computation

**Dependencies:**
- None (purely mathematical)

---

### 6. elastic-chromatic (3,087 bytes)

**Current Visual Description:**
Temporal feedback shader with per-channel exponential moving averages creating "elastic" color trails. Red and blue channels lag behind green, creating temporal chromatic aberration.

**Current Technique:**
- EMA per channel: `New = History * Lag + Curr * (1-Lag)`
- Independent lag factors for R/B channels
- Mouse proximity modulates lag amount

**Artistic Upgrade Concept:**
**"Viscoelastic Photon Dispersion"** - Upgrade to model actual photon transport in dispersive medium with frequency-dependent absorption and scattering. Each wavelength has different mean free path and absorption coefficient.

**Computational Technique to Add:**
- Implement Beer-Lambert law per wavelength: `I = I₀exp(-α(λ)x)`
- Add Rayleigh scattering phase function: `P(θ) ∝ (1 + cos²θ)`
- Model photon diffusion with wavelength-dependent diffusion coefficients
- Simulate fluorescence: absorbed UV re-emitted at visible wavelengths

**Visual Reference:**
Light beam passing through cloudy aquarium with dye—blue light scatters more intensely creating volumetric blue fog, red penetrates deeper creating "red shift" at distance, fluorescent particles glow at different colors.

**Implementation Complexity:** High
- Multi-pass scattering simulation
- Phase function integration
- Requires dataTexture history

**Dependencies:**
- dataTextureC (already used)
- dataTextureB for scattering accumulation

---

### 7. rgb-delay-brush (3,153 bytes)

**Current Visual Description:**
Mouse-driven brush effect with per-channel temporal delay creating RGB smears. Different update speeds per channel inside brush radius create "painting with light" effect.

**Current Technique:**
- Brush mask: `smoothstep(radius, radius * 0.5, dist)`
- Per-channel reaction speeds: `s_r > s_g > s_b`
- Persistence-based trail accumulation

**Artistic Upgrade Concept:**
**"Chromatic Persistence of Vision"** - Upgrade to model human retinal persistence with cone response curves. The brush becomes a psychophysical simulation of how our eyes actually perceive moving color stimuli.

**Computational Technique to Add:**
- Implement LMS cone response functions (Long, Medium, Short wavelength)
- Add opponent process theory: R-G, B-Y channels
- Model chromatic adaptation (von Kries transform)
- Simulate saccadic masking and microsaccades

**Visual Reference:**
Benham's top/optical illusion—apparent colors emerging from black-and-white patterns due to temporal frequency differences in cone responses, creating "impossible" colors that only exist in perception.

**Implementation Complexity:** Medium
- Requires LMS transformation matrix
- Temporal integration of cone responses
- Opponent color conversion

**Dependencies:**
- dataTextureC (history)

---

### 8. hyper-chromatic-delay (3,158 bytes)

**Current Visual Description:**
Enhanced temporal feedback with oscillating RGB offsets and mouse-distance influence. Creates dreamy, fluid trails with breathing/pulsing color separation.

**Current Technique:**
- Oscillating offset: `sin(time * 2.0 + dist * 10.0)`
- Exponential feedback decay
- Mouse influence as additive offset

**Artistic Upgrade Concept:**
**"Gravitational Redshift Simulator"** - Transform into relativistic visualization where time dilation affects color—simulating gravitational redshift near massive objects or Doppler shifts from relativistic motion.

**Computational Technique to Add:**
- Implement gravitational redshift: `z = GM/(rc²)`
- Add relativistic Doppler: color shift based on velocity toward/away
- Simulate Schwarzschild metric for photon trajectories
- Add gravitational lensing: light bending around massive objects

**Visual Reference:**
Interstellar movie black hole visualization—extreme redshift near event horizon, Einstein ring gravitational lensing, photon sphere creating ghost images, color gradients showing time dilation zones.

**Implementation Complexity:** Very High
- Ray marching in curved spacetime
- Relativistic coordinate transformations
- Extensive numerical integration

**Dependencies:**
- dataTextureA, dataTextureC
- May require multi-pass for ray marching

---

### 9. chromatic-mosaic-projector (3,240 bytes)

**Current Visual Description:**
Cellular mosaic effect with per-cell directional projection creating "stained glass" appearance. Light appears to project from mouse through colored cells.

**Current Technique:**
- Grid quantization with cell-centered sampling
- Directional offset based on mouse-to-cell vector
- Per-cell vignetting for rounded cell appearance

**Artistic Upgrade Concept:**
**"Kaleidoscopic Quasicrystal Diffraction"** - Upgrade to simulate diffraction through aperiodic quasicrystal structures (Penrose tiling) with true wave interference creating 10-fold or 12-fold symmetric patterns.

**Computational Technique to Add:**
- Generate Penrose tiling or Ammann-Beenker tiling
- Implement Huygens-Fresnel diffraction integral
- Add phase accumulation from different scattering centers
- Simulate far-field diffraction pattern evolution

**Visual Reference:**
Quasicrystal electron diffraction pattern—sharp Bragg peaks with 10-fold rotational symmetry, self-similar structure at different scales, "forbidden" crystallographic symmetries appearing.

**Implementation Complexity:** Very High
- Requires tiling generation or lookup
- Complex wave interference calculations
- Phase-sensitive accumulation

**Dependencies:**
- storage buffer for tiling vertices (could use plasmaBuffer)

---

### 10. chroma-depth-tunnel (3,453 bytes)

**Current Visual Description:**
Tunnel/torus mapping effect with chromatic aberration in the "tunnel" space. Creates infinite zoom/fall-through sensation with RGB separation along the tunnel axis.

**Current Technique:**
- Polar coordinate transformation: `u = angle/π, v = 1/radius`
- Chromatic offset in V coordinate
- Density modulation of tunnel texture

**Artistic Upgrade Concept:**
**"Wormhole Chromatic Aberration"** - Upgrade to simulate traversable wormhole (Morris-Thorne metric) with accurate gravitational lensing and chromatic effects from differential photon path lengths.

**Computational Technique to Add:**
- Implement Morris-Thorne wormhole metric
- Ray marching through wormhole throat
- Add chromatic aberration from differential time delay
- Simulate frame dragging and tidal forces

**Visual Reference:**
Interstellar wormhole visualization—spherical opening distorting background stars, Einstein ring around the "mouth", smooth transition through throat, second universe visible at end of tunnel.

**Implementation Complexity:** Very High
- Extensive ray marching required
- Curved spacetime geodesic integration
- Multiple render passes for different wavelengths

**Dependencies:**
- dataTextureA for accumulation
- May need compute pass for ray batching

---

### 11. chroma-kinetic (3,606 bytes)

**Current Visual Description:**
Luminance-modulated chromatic displacement with rotation. Bright areas experience stronger color separation, creating "HDR-aware" chromatic aberration.

**Current Technique:**
- Luma extraction: `dot(color.rgb, vec3(0.299, 0.587, 0.114))`
- Luma-modulated offset magnitude
- Rotation transformation of offset direction

**Artistic Upgrade Concept:**
**"Spectral Photon Flux Density"** - Upgrade to model actual spectral radiance with physically-based light transport. Bright areas are treated as high photon flux with wavelength-dependent scattering.

**Computational Technique to Add:**
- Convert RGB to spectral radiance via basis functions
- Implement radiative transfer equation along view rays
- Add wavelength-dependent phase functions
- Simulate stimulated emission in high-flux regions

**Visual Reference:**
High-energy physics particle detector visualization—bright tracks showing Cherenkov radiation (blue cone), energy-dependent color shifts, density of ionization trails.

**Implementation Complexity:** Very High
- Spectral basis function reconstruction
- Numerical radiative transfer integration
- Complex physics simulation

**Dependencies:**
- dataTextureA for radiance accumulation

---

### 12. chroma-vortex (3,851 bytes)

**Current Visual Description:**
Rotational vortex with RGB channels rotated at different angles creating chromatic twist. RGB separation increases with distance from center in angular space.

**Current Technique:**
- Aspect-corrected rotation: `rotate(diff * aspect) / aspect`
- Per-channel rotation angle offset
- Smooth falloff from rotation center

**Artistic Upgrade Concept:**
**"Accretion Disk Spectroscopy"** - Transform into simulation of matter spiraling into black hole with relativistic beaming, gravitational redshift, and Doppler shifts creating extreme chromatic effects.

**Computational Technique to Add:**
- Implement Keplerian orbital velocities
- Add relativistic beaming: `I(θ) = I₀/γ⁴(1-βcosθ)⁴`
- Gravitational redshift based on radius
- Simulate blackbody spectrum from heated disk

**Visual Reference:**
Black hole accretion disk (M87* image)—bright approaching side (blueshifted), dim receding side (redshifted), dark central shadow, photon ring creating thin bright circle.

**Implementation Complexity:** Very High
- Relativistic radiation transport
- Orbital mechanics integration
- Blackbody spectrum generation

**Dependencies:**
- dataTextureA for disk density accumulation

---

### 13. chromatic-focus-interactive (3,708 bytes)

**Current Visual Description:**
Enhanced depth-of-field with configurable hardness/falloff curve and click-to-set focus ring visualization. More sophisticated falloff control than basic chromatic-focus.

**Current Technique:**
- Power-law falloff: `pow(amount, 1.0/hardness)`
- Focus ring visualization on click
- 3-tap RGB sampling with offset

**Artistic Upgrade Concept:**
**"Adaptive Optics Wavefront Correction"** - Upgrade to simulate telescope adaptive optics system where aberrations are measured (via wavefront sensor) and corrected in real-time, showing uncorrected vs corrected views.

**Computational Technique to Add:**
- Generate Kolmogorov turbulence phase screens
- Implement Shack-Hartmann wavefront sensor simulation
- Add deformable mirror correction patterns
- Simulate Strehl ratio and point-spread function

**Visual Reference:**
Astronomical telescope images before/after adaptive optics—turbulent, dancing blur becoming sharp diffraction-limited image, speckle patterns evolving in real-time, artificial laser guide star visible.

**Implementation Complexity:** Very High
- Atmospheric turbulence simulation
- Fourier optics for wave propagation
- Real-time phase screen generation

**Dependencies:**
- dataTextureB for phase screen storage
- Multiple compute passes

---

### 14. chromatic-swirl (4,254 bytes)

**Current Visual Description:**
Smooth swirl rotation with chromatic offset along radius. Creates liquid-like vortex with RGB channels following different spiral paths.

**Current Technique:**
- Quadratic swirl falloff: `angle = percent² * strength`
- Per-frame time animation option
- Mouse click intensity boost

**Artistic Upgrade Concept:**
**"Superfluid Helium Vortex Colors"** - Upgrade to simulate quantum vortices in superfluid helium-4 with irrotational flow, quantized circulation, and phonon-roton spectrum visualization.

**Computational Technique to Add:**
- Implement velocity potential: `v = ℏ/m ∇φ`
- Add quantized vortices: `∮v·dl = nℏ/m`
- Simulate phonon dispersion: `E(p) = c|p| for p→0`
- Show roton minimum and maxon in spectrum

**Visual Reference:**
Superfluid helium rotating in bucket—array of quantized vortices forming regular lattice, normal fluid component vs superfluid component separation, quantum turbulence cascade.

**Implementation Complexity:** High
- Complex fluid dynamics simulation
- Quantum mechanics implementation
- Vortex tracking and interaction

**Dependencies:**
- dataTextureA for vortex position storage
- extraBuffer for vortex array

---

### 15. chromatic-folds-gemini (7,474 bytes)

**Current Visual Description:**
Fractalized psychedelic topology with multi-layer folding, vortex manipulation, and hue-based displacement. Creates complex, evolving color patterns with depth-aware distortion.

**Current Technique:**
- 3-layer fractal folding with octave scaling
- Vortex displacement: `angle + strength/r * sin(r * 10 - time)`
- Hue gradient-based displacement with wrap-around handling
- Feedback persistence for temporal evolution

**Artistic Upgrade Concept:**
**"Conformal Mapping Visualization"** - Upgrade to proper complex analysis visualization showing analytic functions as domain coloring with poles, zeros, and branch cuts clearly visible through chromatic encoding.

**Computational Technique to Add:**
- Implement domain coloring: `arg(f(z)) → hue, |f(z)| → value`
- Add Riemann sphere projection
- Show branch cuts with hue discontinuities
- Visualize essential singularities (Great Picard Theorem)

**Visual Reference:**
Complex function domain coloring—rainbow swirl showing argument of function, brightness showing magnitude, distinctive patterns around poles (rainbow cycles) and zeros (fades to black), branching logarithmic spirals.

**Implementation Complexity:** High
- Complex number arithmetic throughout
- Careful handling of branch cuts
- Potential numerical precision issues

**Dependencies:**
- None (mathematical)

---

### 16. chromatic-folds (14,266 bytes)

**Current Visual Description:**
Sophisticated hue-gradient displacement with depth-curvature tensor. Treats image as 4D manifold (x, y, depth, hue) with topological folding operations.

**Current Technique:**
- Finite difference hue gradient computation
- Wrap-around gradient for hue discontinuity
- Depth curvature: `pow(depth, 2) * influence`
- Hue folding function: `foldHue(pivot + sign(δ) * pow(|δ|, strength))`

**Artistic Upgrade Concept:**
**"Differential Geometry of Color Space"** - Upgrade to full Riemannian geometry on color manifold with metric tensor, Christoffel symbols, and geodesic flow visualization.

**Computational Technique to Add:**
- Define color space metric tensor g_μν
- Compute Christoffel symbols Γᵏᵢⱼ
- Implement geodesic equation integration
- Visualize Ricci curvature and scalar curvature

**Visual Reference:**
General relativity visualization with embedding diagrams—color space distorted by "mass" of high-saturation colors, geodesic lines (shortest color transitions) bending around high-chroma regions, event horizons around pure colors.

**Implementation Complexity:** Extremely High
- Tensor calculus in WGSL
- Numerical ODE integration for geodesics
- Curvature tensor computation

**Dependencies:**
- dataTextureB for metric storage
- Multiple passes for tensor computation

---

### 17. chromatic-folds-2 (13,489 bytes)

**Current Visual Description:**
Topologically complex shader implementing Möbius, Klein bottle, and hyperbolic folds in color space. Quaternion rotations and recursive color space compression.

**Current Technique:**
- Möbius strip fold with channel swapping
- Klein bottle non-orientable surface
- Hyperbolic fold with logarithmic distance
- Quaternion rotation in 4D projected to 3D

**Artistic Upgrade Concept:**
**"Fiber Bundle Topology Visualization"** - Upgrade to visualize fiber bundles, vector bundles, and characteristic classes from algebraic topology with color representing fiber structure over base manifold.

**Computational Technique to Add:**
- Implement Hopf fibration visualization
- Add tangent bundle with connection forms
- Show curvature of connection (field strength)
- Visualize Chern classes and Pontryagin classes

**Visual Reference:**
Hopf fibration visualization—nested torus surfaces showing how 3-sphere maps to 2-sphere with circle fibers, stereographic projection showing linked circles, elegant spiral structure of fiber bundle.

**Implementation Complexity:** Extremely High
- Abstract topology implementation
- Bundle connection mathematics
- Characteristic class computation

**Dependencies:**
- May need storage buffers for bundle data

---

### 18. chromatic-manifold (9,528 bytes)

**Current Visual Description:**
4D neighbor search with k-nearest-neighbors approximation in (u, v, depth, hue) space. Estimates tangent frames and applies hue-gradient warping.

**Current Technique:**
- KNN search in 4D space (brute force in window)
- Tangent frame computation from neighbors
- Linear regression for gradient estimation
- HDR tear detection and smearing

**Artistic Upgrade Concept:**
**"Manifold Learning Embedding"** - Upgrade to implement actual dimensionality reduction algorithms (t-SNE, UMAP) running on GPU, visualizing high-dimensional data projected to 2D with color preserving original structure.

**Computational Technique to Add:**
- Implement t-SNE or UMAP algorithm in compute shader
- Compute pairwise affinities in high-dimensional space
- Gradient descent for low-dimensional embedding
- Color by original high-dimensional distance

**Visual Reference:**
MNIST t-SNE visualization—clusters of handwritten digits clearly separated in 2D projection, gradual color transitions showing continuous paths between classes, local neighborhoods preserved.

**Implementation Complexity:** Very High
- Iterative optimization algorithm
- Global pairwise computation
- Requires multiple dispatch passes

**Dependencies:**
- extraBuffer for embedding state
- Multiple data textures for affinity matrices

---

### 19. chromatic-manifold-2 (14,645 bytes)

**Current Visual Description:**
Enhanced version with Möbius-like hue folding, depth curvature tensor, and growing feedback folds. More sophisticated ripple interaction with depth-aware propagation speed.

**Current Technique:**
- Same base as chromatic-manifold
- Enhanced foldHue with power-law distortion
- Depth-aware ripple speed: `speed = mix(1.0, 2.0, 1.0 - depth)`
- Feedback persistence with temporal accumulation

**Artistic Upgrade Concept:**
**"Ricci Flow on Color Manifold"** - Implement Hamilton's Ricci flow that evolves metric to uniformize curvature, visualizing how color space "flows" toward constant curvature.

**Computational Technique to Add:**
- Implement Ricci tensor computation
- Evolve metric via ∂g/∂t = -2Ric
- Visualize curvature evolution over time
- Show convergence to constant curvature (Poincaré conjecture)

**Visual Reference:**
Ricci flow visualization—initially irregular manifold smoothing out over time, "neck pinch" singularities forming and resolving, final spherical or flat geometry achieved.

**Implementation Complexity:** Extremely High
- Time-dependent metric evolution
- Singularity detection and surgery
- Complex tensor calculus

**Dependencies:**
- dataTextureB for time-evolving metric
- extensive storage buffer usage

---

### 20. chromatic-crawler (15,389 bytes)

**Current Visual Description:**
Chaotic color-swapping with Voronoi-based crawling regions. Rapid color exchanges between areas with temporal flashing and glow effects.

**Current Technique:**
- Animated Voronoi region generation
- Multiple crawling centers with Lissajous motion
- 6-pattern color swapping system
- Temporal color modulation with hash-based randomness

**Artistic Upgrade Concept:**
**"Reaction-Diffusion Turing Patterns"** - Replace chaotic swapping with Gray-Scott or FitzHugh-Nagumo reaction-diffusion system producing emergent, organic patterns that evolve naturally.

**Computational Technique to Add:**
- Implement Gray-Scott model: `∂u/∂t = D_u∇²u - uv² + F(1-u)`
- Add feed rate F and kill rate K parameter variation
- Multiple chemical species with different diffusion rates
- Pattern selection via parameter space exploration

**Visual Reference:**
Belousov-Zhabotinsky reaction or animal coat patterns—spots, stripes, and labyrinthine patterns emerging from simple rules, coral-like growth, leopard print, zebra stripes.

**Implementation Complexity:** Medium-High
- Laplacian stencil computation
- Multiple chemical species
- Requires double-buffering (dataTextureA/B)

**Dependencies:**
- dataTextureA and dataTextureB for species concentrations

---

### 21. chroma-lens (4,439 bytes)

**Current Visual Description:**
Magnifying lens effect with barrel distortion and chromatic aberration. Simulates glass lens with rim reflection and edge blur.

**Current Technique:**
- Parabolic lens curve: `lensCurve = 1.0 - (1.0 - ndist²) * mag`
- Per-channel scaling factors for chromatic aberration
- Glass rim highlight effect

**Artistic Upgrade Concept:**
**"Compound Apochromatic Lens"** - Upgrade to accurate lens design simulation with multiple lens elements, different glass types (Abbe numbers), and full optical path tracing for realistic camera lens rendering.

**Computational Technique to Add:**
- Implement Snell's law with wavelength-dependent refractive index
- Trace rays through multiple lens elements
- Model Abbe number dispersion for different glasses
- Add aperture diffraction and vignetting

**Visual Reference:**
Professional camera lens MTF chart visualization—sharp central resolution with smooth falloff, minimal chromatic aberration (achromatic/apochromatic design), smooth bokeh from rounded aperture blades.

**Implementation Complexity:** Very High
- Ray tracing through lens system
- Dispersion data for optical glasses
- Aperture sampling

**Dependencies:**
- May need lens prescription data in uniform buffer

---

### 22. chroma-threads (4,327 bytes)

**Current Visual Description:**
Horizontal "thread" scanlines with per-thread vibration based on mouse proximity. RGB channels vibrate at different amplitudes creating chromatic separation along threads.

**Current Technique:**
- Thread quantization: `floor(uv.y * density)`
- Gaussian-modulated vibration based on X-distance to mouse
- Per-thread vibration with phase coherence
- Thread-edge masking

**Artistic Upgrade Concept:**
**"Cholesteric Liquid Crystal Interference"** - Upgrade to simulate cholesteric liquid crystals (CLC) with helical molecular structure creating selective reflection and circular polarization effects.

**Computational Technique to Add:**
- Implement Bragg reflection from helical structure
- Model pitch variation (temperature/field dependent)
- Add circular polarization state tracking
- Simulate Grandjean-Cano dislocations

**Visual Reference:**
Liquid crystal display under polarized light—iridescent color shifts with viewing angle, fingerprint texture from dislocations, vivid metallic-looking colors from selective reflection.

**Implementation Complexity:** High
- Polarization state tracking (Stokes parameters)
- Helical structure simulation
- Multiple reflection orders

**Dependencies:**
- dataTextureA for helical phase storage

---

## Implementation Priority Matrix

| Shader | Visual Impact | Complexity | Scientific Grounding | Recommended Priority |
|--------|--------------|------------|---------------------|---------------------|
| chromatic-shockwave | High | Medium | Strong | P1 |
| rgb-ripple-distortion | High | Medium | Strong | P1 |
| elastic-chromatic | High | High | Strong | P2 |
| chroma-vortex | Very High | Very High | Strong | P3 |
| chromatic-folds | Very High | Extreme | Strong | P3 |
| chromatic-crawler | High | Medium | Strong | P2 |
| chroma-lens | Medium | Very High | Strong | P3 |
| rgb-delay-brush | Medium | Medium | Strong | P2 |
| chroma-depth-tunnel | High | Very High | Strong | P3 |
| chroma-kinetic | High | Very High | Strong | P3 |

---

## Resource Requirements Summary

| Resource Type | Light Upgrades | Medium Upgrades | Heavy Upgrades |
|--------------|----------------|-----------------|----------------|
| Texture Samples | 3-5 | 5-9 | 9-16+ |
| Data Textures | 1 (C) | 2 (A,C) | 3 (A,B,C) |
| Storage Buffers | None | extraBuffer | extraBuffer + plasmaBuffer |
| Compute Passes | 1 | 1-2 | 2-4 |
| Uniform Parameters | 4 | 4 | 4+ extended range |

---

## Technical Notes

### Spectral Sampling Strategy
For shaders requiring wavelength-dependent effects (Cauchy dispersion, Rayleigh scattering), implement compact spectral representation:
- Sample 7 wavelengths: 650nm, 600nm, 550nm, 500nm, 450nm, 400nm, 380nm
- Use Gaussian basis functions for spectral reconstruction
- Convert to XYZ via CIE color matching functions, then to RGB

### Temporal Feedback Conservation
When upgrading temporal shaders, preserve existing feedback architecture:
- dataTextureC: previous frame input (read-only)
- dataTextureA: next frame output (write-only, becomes C next frame)
- Maintain feedbackMix parameter for blend control

### Performance Considerations
- High-complexity upgrades may require reducing workgroup coverage
- Consider LOD system: simplified version at distance, full version near mouse
- Use early-out for pixels outside effect radius

---

## Conclusion

The chromatic shader family offers rich opportunities for scientifically-grounded visual enhancement. Priority should be given to shaders that can leverage existing temporal feedback infrastructure while adding meaningful physical simulation. The "Prismatic Shockwave" and "Photoelastic Ripple" upgrades offer the best combination of visual impact, scientific validity, and implementation feasibility.

---

*Document Version: 1.0*
*Analysis Date: 2026-03-14*
*Total Shaders Analyzed: 22*
*Total Upgrade Concepts: 22*
