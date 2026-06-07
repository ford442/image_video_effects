# DISTORTION & WARP Category Shader Upgrade Plan

## Executive Summary

This document outlines artistic and computational upgrade pathways for 27 distortion and warp shaders in Pixelocity. Each shader is analyzed against 10 scientific concepts to identify enhancement opportunities that maintain real-time performance while significantly elevating visual fidelity.

---

## Scientific Concepts Reference

| # | Concept | Mathematical Foundation | Visual Characteristic |
|---|---------|------------------------|----------------------|
| 1 | General Relativity Gravitational Lensing | Einstein field equations, light deflection angle α = 4GM/(c²b) | Einstein rings, arc distortions, multiple images |
| 2 | Schwarzschild Metric | ds² = -(1-rₛ/r)c²dt² + (1-rₛ/r)⁻¹dr² + r²dΩ² | Event horizons, photon spheres, causal disconnection |
| 3 | Spacetime Curvature Visualization | Riemann curvature tensor R^μ_{νρσ} | Geodesic deviation, tidal stretching, frame dragging |
| 4 | Fluid Vorticity and Curl | ω = ∇ × u, circulation Γ = ∮u·dl | Swirl patterns, vortex shedding, turbulent cascades |
| 5 | Conformal Mappings | f(z) analytic, preserves angles | Möbius transforms, Joukowsky airfoils, Escher tilings |
| 6 | Elastic Deformation Physics | Stress σ = Eε, strain energy U = ½σε | Spring-mass systems, finite element warping, Hookean response |
| 7 | Acoustic Shockwave Propagation | Mach cone sin(μ) = 1/M, Rankine-Hugoniot | Compression fronts, rarefaction waves, sonic booms |
| 8 | Ray Bending in Atmospheric Layers | dn/dh refraction gradient, mirage condition | Fata morgana, superior/inferior mirages, looming |
| 9 | Fisheye Projection Mathematics | Stereographic: r = 2f·tan(θ/2), Equidistant: r = f·θ | Hemispherical coverage, angular preservation, equal-area |
| 10 | Barrel/Pincushion Distortion Models | r_d = r_u(1 + κ₁r² + κ₂r⁴) | Radial distortion correction, lens aberration simulation |

---

## Shader Upgrade Analysis

### TIER 1: Gravitational Physics Cluster

#### 1. gravity-lens → "Relativistic Lensing Suite"
**Current State:** 5,282 bytes - Basic 1/r lens equation with chromatic offset
**Scientific Upgrade:** Concept #1 + #2 (GR Lensing + Schwarzschild)

**Artistic Vision:**
Transform the current weak-field approximation into a full strong-field gravitational lensing simulator. The upgrade should render the iconic "Einstein cross" and "arc" phenomena seen in Hubble deep field images.

**Computational Enhancements:**
- Replace 1/r deflection with exact Schwarzschild geodesic tracing
- Implement the lens equation: β = θ - α(θ) where α is the reduced deflection angle
- Add critical curve visualization (where det(∂β/∂θ) = 0)
- Include caustic structure in the source plane

**Parameter Expansion:**
- `mass_ratio`: Dimensionless mass M/rₛ (0.1 to 10)
- `impact_parameter`: Normalized impact parameter b/rₛ
- `source_distance`: Ratio of source/lens distances D_ls/D_s
- `spin`: Kerr parameter a = Jc/GM² (0 to 0.998 for realistic BH)

**Visual Features:**
- Einstein ring formation at perfect alignment
- Arc distortion for extended sources
- Tangential/cradle stretching vs radial compression
- Gravitational time delay color shifting (Shapiro delay)

---

#### 2. gravity-well → "Accretion Dynamics"
**Current State:** 4,205 bytes - Simple pinch with glow ring
**Scientific Upgrade:** Concept #2 + #3 (Schwarzschild + Spacetime Curvature)

**Artistic Vision:**
Evolve from a static lens to a dynamic black hole environment with accretion disk physics and frame-dragging visualization.

**Computational Enhancements:**
- Add photon sphere integration (r = 3rₛ for Schwarzschild)
- Implement Doppler beaming from rotating disk
- Gravitational redshift z = (1 - rₛ/r)⁻¹/² - 1
- Light bending through 360° for photon ring

**Visual Features:**
- Asymmetric accretion disk (relativistic beaming)
- Blue-shifted approaching side, red-shifted receding side
- Photon ring (secondary image of disk)
- Shadow silhouette (Event Horizon Telescope style)

---

#### 3. vortex → "Geodesic Flow Visualization"
**Current State:** Uses zoom layers with depth parallax
**Scientific Upgrade:** Concept #3 (Spacetime Curvature)

**Artistic Vision:**
Reimagine the zoom effect as matter flowing along geodesics in curved spacetime, showing tidal deformation.

**Computational Enhancements:**
- Tidal tensor visualization: C_ij = R_i0j0
- Geodesic deviation equation: d²ξ^i/dτ² = -R^i_{0j0}ξ^j
- Frame dragging angular velocity: ω = 2GJ/r³
- Ergosphere visualization for rotating black holes

---

### TIER 2: Fluid Dynamics Cluster

#### 4. vortex-distortion → "Navier-Stokes Vortex"
**Current State:** 3,980 bytes - Simple rotation with falloff
**Scientific Upgrade:** Concept #4 (Fluid Vorticity and Curl)

**Artistic Vision:**
Transform from rigid rotation to proper fluid vortex dynamics with velocity fields that satisfy ∇·u = 0 (incompressibility).

**Computational Enhancements:**
- Velocity potential formulation: u = ∇×ψ
- Lamb-Oseen vortex: u_θ = (Γ/2πr)(1 - exp(-r²/4νt))
- Vorticity transport equation: Dω/Dt = ν∇²ω
- Rankine vortex core (solid body rotation inside, irrotational outside)

**Parameter Expansion:**
- `circulation`: Γ parameter controlling swirl strength
- `core_radius`: Transition from solid to irrotational flow
- `viscosity`: ν for diffusion of vorticity
- `vortex_age`: Time since formation (affects core size)

**Visual Features:**
- Velocity magnitude visualization (speed coloring)
- Streamline integration showing pathlines
- Vortex stretching and tilting (3D effect simulation)
- Kelvin-Helmholtz instability at shear layers

---

#### 5. vortex-warp → "Turbulent Cascade"
**Current State:** 4,037 bytes - Rotation with spiral
**Scientific Upgrade:** Concept #4 (Vorticity) + #5 (Conformal Mappings)

**Artistic Vision:**
Create a hierarchy of vortices at different scales, simulating turbulent energy cascade from large to small eddies.

**Computational Enhancements:**
- Implement vortex lattice: multiple interacting vortices
- Biot-Savart law for velocity induced by vortex filaments
- Kolmogorov energy spectrum: E(k) ~ k^(-5/3)
- Conformal map composition for nested vortices

---

#### 6. vortex-drag → "Interactive Vorticity Field"
**Current State:** 3,169 bytes - Twist and pinch
**Scientific Upgrade:** Concept #4 (Fluid Vorticity) + #6 (Elastic Deformation)

**Artistic Vision:**
Combine fluid vortex dynamics with elastic response for a "dragging through viscous fluid" sensation.

**Computational Enhancements:**
- Vorticity generation at mouse position: ∂ω/∂t = -u·∇ω
- Lagrangian particle tracking in velocity field
- Viscoelastic stress integration
- Two-way coupling between image and fluid

---

#### 7. vortex-prism → "Dispersive Vortex"
**Current State:** 4,426 bytes - Twist with RGB separation
**Scientific Upgrade:** Concept #4 + #8 (Vorticity + Atmospheric Ray Bending)

**Artistic Vision:**
Elevate the prismatic separation to chromatic dispersion in a rotating medium, simulating dispersion in optical vortices.

**Computational Enhancements:**
- Wavelength-dependent refractive index: n(λ)
- Angular dispersion: dθ/dλ
- Orbital angular momentum of light (OAM)
- Color-dependent vortex core sizes

---

### TIER 3: Complex Analysis Cluster

#### 8. infinite-spiral-zoom → "Conformal Iteration"
**Current State:** 3,277 bytes - Log-polar with twist
**Scientific Upgrade:** Concept #5 (Conformal Mappings)

**Artistic Vision:**
Leverage the power of complex analysis to create infinitely recursive conformal transformations that preserve local angles.

**Computational Enhancements:**
- Möbius transformation: f(z) = (az + b)/(cz + d)
- Joukowsky transform: f(z) = z + 1/z (airfoil shapes)
- Schwarz-Christoffel mapping: polygon boundaries
- Modular lambda function for tiling

**Parameter Expansion:**
- `a,b,c,d`: Complex coefficients for Möbius
- `exponent`: z^n for n-fold symmetry
- `poles`: Location of singularities
- `modular_tau`: Torus parameter for doubly-periodic

**Visual Features:**
- Circular grid lines remain circular/orthogonal
- Droste effect with conformal constraints
- Escher-style impossible tilings
- Modular forms and elliptic curves visualization

---

#### 9. julia-warp → "Holomorphic Dynamics"
**Current State:** Complex fractal warping
**Scientific Upgrade:** Concept #5 (Conformal Mappings) + Julia sets

**Artistic Vision:**
Combine Julia set iteration with conformal warping to create self-similar distortion fields.

**Computational Enhancements:**
- Fatou/Julia set boundary as distortion field
- External rays and equipotential lines
- Böttcher coordinate mapping
- Hyperbolic components of Mandelbrot parameter space

---

#### 10. fractal-glass-distort → "Iterated Function System"
**Current State:** 3,751 bytes - Recursive rotation layers
**Scientific Upgrade:** Concept #5 (Conformal) + #10 (Lens Distortion)

**Artistic Vision:**
Transform the 4-layer recursion into a proper IFS (Iterated Function System) with Hutchinson operator.

**Computational Enhancements:**
- Contractive affine transformations: w_i(x) = A_i x + b_i
- Barnsley fern and Sierpinski attractors
- De Rham curve construction
- Fractal interpolation functions

---

### TIER 4: Elasticity & Deformation Cluster

#### 11. elastic-strip → "Finite Element Warp"
**Current State:** 3,449 bytes - Strip displacement
**Scientific Upgrade:** Concept #6 (Elastic Deformation Physics)

**Artistic Vision:**
Implement proper elasticity theory with strain-stress relationships for physically-based image deformation.

**Computational Enhancements:**
- Green-Lagrange strain tensor: E = ½(F^T F - I)
- Neo-Hookean material model: W = μ/2(tr(C) - 3) - μ ln J + λ/2 (ln J)²
- Cloth simulation with bending energy
- Mass-spring-damper systems

**Parameter Expansion:**
- `youngs_modulus`: E stiffness
- `poisson_ratio`: ν (0 to 0.5)
- `shear_modulus`: G = E/(2(1+ν))
- `damping`: η for viscoelastic response

**Visual Features:**
- Stress concentration at boundaries
- Poisson effect (contraction perpendicular to stretch)
- Buckling and wrinkling instabilities
- Elastic wave propagation

---

#### 12. slinky-distort → "Wave Mechanics"
**Current State:** 2,942 bytes - Sine wave band offset
**Scientific Upgrade:** Concept #6 + #7 (Elasticity + Acoustic Waves)

**Artistic Vision:**
Transform from simple sine displacement to proper wave equation solutions with dispersion and group velocity.

**Computational Enhancements:**
- Wave equation: ∂²u/∂t² = c² ∇²u
- D'Alembert solution: u(x,t) = f(x-ct) + g(x+ct)
- Dispersion relation: ω(k) for different media
- Superposition and interference patterns

---

#### 13. ripple-blocks → "Discrete Elastic Media"
**Current State:** 3,827 bytes - Block scaling with waves
**Scientific Upgrade:** Concept #6 (Elastic Deformation)

**Artistic Vision:**
Treat each block as a discrete elastic element with mass and spring connections to neighbors.

**Computational Enhancements:**
- Lattice dynamics with nearest-neighbor springs
- Phonon dispersion relations
- Band structure for periodic media
- Localized modes at defects

---

### TIER 5: Acoustic & Shock Cluster

#### 14. sonic-distortion → "Shock Wave Physics"
**Current State:** 2,926 bytes - Radial sine wave
**Scientific Upgrade:** Concept #7 (Acoustic Shockwave Propagation)

**Artistic Vision:**
Transform from gentle waves to realistic shock physics with compression fronts and Mach cones.

**Computational Enhancements:**
- Mach angle: μ = arcsin(1/M) where M = v_source/c
- Rankine-Hugoniot jump conditions
- Blast wave (Sedov-Taylor): r(t) = β(Et²/ρ)^(1/5)
- N-wave for sonic booms

**Parameter Expansion:**
- `mach_number`: M from 0.8 (transonic) to 5+ (hypersonic)
- `blast_energy`: E for explosion strength
- `attenuation`: Distance decay exponent
- `wave_speed`: c in medium

**Visual Features:**
- Sharp compression front with gradual rarefaction
- Mach cone geometry for supersonic
- N-wave double shock signature
- Triple point intersection

---

#### 15. hyper-space-jump → "Relativistic Doppler"
**Current State:** 4,236 bytes - Radial blur with chromatic separation
**Scientific Upgrade:** Concept #7 + #3 (Shock + Spacetime)

**Artistic Vision:**
Add relativistic effects to the hyperspace jump, including proper aberration of light and Doppler shifting.

**Computational Enhancements:**
- Relativistic Doppler: f_observed = f_source √[(1-β)/(1+β)]
- Aberration formula: cos θ' = (cos θ - β)/(1 - β cos θ)
- Terrell rotation (Penrose-Terrell effect)
- Starfield distortion at relativistic speeds

---

#### 16. warp_drive → "Alcubierre Metric Visualization"
**Current State:** 4,274 bytes - Radial blur with glow
**Scientific Upgrade:** Concept #3 + #7 (Spacetime + Shock)

**Artistic Vision:**
Model the Alcubierre warp drive metric with contraction in front and expansion behind the spacecraft.

**Computational Enhancements:**
- Alcubierre metric: ds² with warp function f(r_s)
- Expansion θ and shear σ of null geodesics
- Horizon formation for superluminal travel
- Tidal forces in the warp bubble

---

### TIER 6: Atmospheric & Optical Cluster

#### 17. radiating-haze → "Atmospheric Refraction"
**Current State:** 7,005 bytes - Color-based aura
**Scientific Upgrade:** Concept #8 (Ray Bending in Atmospheric Layers)

**Artistic Vision:**
Transform the simple color aura into realistic atmospheric optical phenomena including mirages and looming.

**Computational Enhancements:**
- Refraction integral: ∫(dn/dh) ds for curved paths
- Temperature gradient profiles (lapse rate)
- Superior/inferior mirage conditions
- Astronomical refraction: R = R₀ tan ζ

**Parameter Expansion:**
- `temperature_gradient`: dT/dh (K/m)
- `humidity_profile`: Affects refractive index
- `wavelength`: n(λ) dispersion
- `observer_height`: For horizon calculations

**Visual Features:**
- Fata morgana (complex superior mirage)
- Looming and sinking effects
- Green flash at sunset
- Inferior mirage "water" effects

---

#### 18. radiating-displacement → "Atmospheric Scintillation"
**Current State:** 6,748 bytes - Wave displacement
**Scientific Upgrade:** Concept #8 (Atmospheric Ray Bending)

**Artistic Vision:**
Evolve the displacement waves to simulate atmospheric turbulence and scintillation (twinkling).

**Computational Enhancements:**
- Fried parameter r₀ for turbulence strength
- Phase structure function D_φ(r) = 6.88 (r/r₀)^(5/3)
- Kolmogorov turbulence spectrum
- Scintillation index σ²_I

---

#### 19. heat-haze → "Turbulent Convection"
**Current State:** Heat shimmer effect
**Scientific Upgrade:** Concept #8 + #4 (Atmospheric + Fluid)

**Artistic Vision:**
Ground the heat haze in proper buoyancy-driven convection physics with rising plumes.

**Computational Enhancements:**
- Rayleigh-Bénard convection cells
- Plume rise equations
- Schlieren visualization of density gradients
- Hot-wire anemometer response

---

### TIER 7: Optical Projection Cluster

#### 20. interactive-fisheye → "Lens Projection Atlas"
**Current State:** 2,836 bytes - Simple barrel distortion
**Scientific Upgrade:** Concept #9 (Fisheye Projection Mathematics)

**Artistic Vision:**
Expand from single fisheye to comprehensive projection type selector covering all major mapping functions.

**Computational Enhancements:**
- Stereographic: r = 2f tan(θ/2) — conformal, preserves circles
- Equidistant: r = f θ — preserves distances from center
- Equisolid: r = 2f sin(θ/2) — preserves area
- Orthographic: r = f sin θ — parallel projection
- Pannini: cylindrical + perspective blend

**Parameter Expansion:**
- `projection_type`: Selector between 5+ mappings
- `focal_length`: f parameter
- `field_of_view`: θ_max up to 360°
- `center_shift`: Decentering distortion

**Visual Features:**
- 180° and 360° full sphere coverage
- Little planet projection (stereographic)
- Hammer-Aitoff equal area
- Cube map and dual fisheye

---

#### 21. bubble-lens → "Thick Lens Optics"
**Current State:** 2,901 bytes - Spherical magnification
**Scientific Upgrade:** Concept #10 + #9 (Distortion + Fisheye)

**Artistic Vision:**
Transform from thin lens approximation to thick lens with actual ray tracing through spherical interface.

**Computational Enhancements:**
- Snell's law at spherical surface: n₁ sin θ₁ = n₂ sin θ₂
- Matrix methods (ABCD ray transfer)
- Spherical aberration calculation
- Chromatic aberration from dispersion

---

#### 22. parallax-shift → "Stereoscopic Disparity"
**Current State:** 2,667 bytes - Luma-based depth parallax
**Scientific Upgrade:** Concept #9 + #10 (Fisheye + Distortion)

**Artistic Vision:**
Enhance the parallax with proper stereoscopic vision simulation including binocular disparity and vergence.

**Computational Enhancements:**
- Disparity map from depth: d = Bf/Z
- Vergence-accommodation conflict
- Panum's fusional area
- Cyclopean viewpoint synthesis

---

### TIER 8: Advanced Interaction Cluster

#### 23. mirror-drag → "Catoptric Surfaces"
**Current State:** 3,135 bytes - Simple flip
**Scientific Upgrade:** Concept #10 + #6 (Distortion + Elastic)

**Artistic Vision:**
Transform from flat mirror to curved reflective surfaces (concave/convex) with caustics.

**Computational Enhancements:**
- Mirror equation: 1/f = 1/d₀ + 1/dᵢ
- Caustic curve generation
- Anamorphic distortion
- Parabolic concentrator focus

---

#### 24. block-distort-interactive → "Discrete Element Method"
**Current State:** 3,778 bytes - Grid push
**Scientific Upgrade:** Concept #6 (Elastic Deformation)

**Artistic Vision:**
Treat blocks as rigid bodies with contact physics and friction.

**Computational Enhancements:**
- Contact detection and response
- Coulomb friction model
- Block packing and jamming
- Force chain visualization

---

#### 25. pixel-drag-smear → "Viscoelastic Smear"
**Current State:** 3,452 bytes - History feedback
**Scientific Upgrade:** Concept #6 + #4 (Elasticity + Fluid)

**Artistic Vision:**
Add memory effects with stress relaxation and thixotropic behavior.

**Computational Enhancements:**
- Maxwell model: stress relaxation
- Kelvin-Voigt model: creep
- Oldroyd-B viscoelastic fluid
- Yield stress (Bingham plastic)

---

#### 26. infinite-zoom-lens → "Feedback Recursion"
**Current State:** 3,450 bytes - Feedback with rotation
**Scientific Upgrade:** Concept #5 + #10 (Conformal + Distortion)

**Artistic Vision:**
Apply conformal constraints to the recursive feedback to create Escher-like impossible zooms.

**Computational Enhancements:**
- Conformally invariant iterations
- Logarithmic spiral self-similarity
- Golden ratio φ = (1+√5)/2 proportions
- Droste effect with complex exponentiation

---

#### 27. polar-warp-interactive → "Riemann Surface"
**Current State:** 3,285 bytes - Polar remapping
**Scientific Upgrade:** Concept #5 (Conformal Mappings)

**Artistic Vision:**
Extend to multi-sheeted Riemann surfaces with branch cuts.

**Computational Enhancements:**
- Branch point singularities
- Monodromy around branch cuts
- Covering space visualization
- Complex logarithm multi-valuedness

---

## Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)
- Implement mathematical utilities:
  - Complex number operations
  - 2x2 and 3x3 matrix math
  - Numerical integration (Runge-Kutta)
  - Root finding (Newton-Raphson)

### Phase 2: Core Clusters (Weeks 3-6)
| Week | Focus Shaders | Scientific Concept |
|------|---------------|-------------------|
| 3 | gravity-lens, gravity-well | GR Lensing |
| 4 | vortex-distortion, vortex-drag | Fluid Vorticity |
| 5 | infinite-spiral-zoom, julia-warp | Conformal Mappings |
| 6 | elastic-strip, slinky-distort | Elasticity |

### Phase 3: Specialized Effects (Weeks 7-10)
| Week | Focus Shaders | Scientific Concept |
|------|---------------|-------------------|
| 7 | sonic-distortion, hyper-space-jump | Acoustic/Shock |
| 8 | radiating-haze, radiating-displacement | Atmospheric |
| 9 | interactive-fisheye, bubble-lens | Optical Projection |
| 10 | mirror-drag, polar-warp-interactive | Advanced Interaction |

### Phase 4: Polish (Week 11-12)
- Performance optimization
- Parameter UI refinement
- Edge case handling
- Cross-shader compatibility testing

---

## Technical Specifications

### Uniform Buffer Additions
```wgsl
// For gravitational lensing
struct GravitationalParams {
    mass_ratio: f32,           // M/r_s
    impact_parameter: f32,     // b/r_s
    source_distance: f32,      // D_ls/D_s
    spin: f32,                 // a = Jc/GM²
};

// For fluid dynamics
struct FluidParams {
    circulation: f32,          // Γ
    viscosity: f32,            // ν
    density: f32,              // ρ
    reynolds_number: f32,      // Re
};

// For conformal mappings
struct ConformalParams {
    a_real: f32, a_imag: f32, // Complex a
    b_real: f32, b_imag: f32, // Complex b
    c_real: f32, c_imag: f32, // Complex c
    d_real: f32, d_imag: f32, // Complex d
};

// For elasticity
struct ElasticParams {
    youngs_modulus: f32,       // E
    poisson_ratio: f32,        // ν
    shear_modulus: f32,        // G
    damping: f32,              // η
};
```

### Helper Functions Library
```wgsl
// Complex arithmetic
fn cmul(a: vec2<f32>, b: vec2<f32>) -> vec2<f32>
fn cdiv(a: vec2<f32>, b: vec2<f32>) -> vec2<f32>
fn cexp(z: vec2<f32>) -> vec2<f32>
fn clog(z: vec2<f32>) -> vec2<f32>

// Gravitational lensing
fn schwarzschild_deflection(b: f32, M: f32) -> f32
fn einstein_radius(M: f32, D: f32) -> f32

// Fluid dynamics
fn lamb_oseen_vortex(r: f32, Gamma: f32, nu: f32, t: f32) -> f32
fn velocity_potential(psi: vec2<f32>) -> vec2<f32>

// Elasticity
fn green_lagrange_strain(F: mat2x2<f32>) -> mat2x2<f32>
fn neo_hookean_stress(F: mat2x2<f32>, mu: f32, lambda: f32) -> mat2x2<f32>
```

---

## Performance Considerations

### Optimization Strategies
1. **Level-of-Detail**: Reduce iteration count for distant/less important regions
2. **Lookup Tables**: Precompute expensive functions (log, atan, sqrt)
3. **Early Exit**: Skip computation for pixels outside effect radius
4. **Approximation**: Use Taylor series for small arguments
5. **Branch Coherence**: Minimize divergent branches within workgroups

### Target Frame Rates
- **Desktop (dGPU)**: 60fps at 1080p with all effects
- **Laptop (iGPU)**: 30fps at 1080p with quality reduction
- **Mobile**: 30fps at 720p with simplified physics

---

## Artistic Direction Guidelines

### Visual Coherence Principles
1. **Physical Plausibility**: Effects should look like they could exist in nature
2. **Scale Appropriateness**: Parameters should map to real-world units
3. **Temporal Consistency**: Animations should respect causality
4. **Energy Conservation**: Brightness changes should be justified

### Color Science Integration
- Use perceptually uniform color spaces (Oklab, IPT)
- Implement proper HDR tone mapping
- Respect material color constancy
- Consider color blindness accessibility

---

## Conclusion

This upgrade plan transforms the distortion category from a collection of ad-hoc effects into a cohesive suite of physically-grounded visualizations. By leveraging established scientific principles, each shader gains:

1. **Authenticity**: Real physics creates believable visuals
2. **Predictability**: Users can reason about parameter effects
3. **Educational Value**: Shaders become teaching tools
4. **Extensibility**: New effects emerge from combining principles

The roadmap prioritizes foundational work before advanced features, ensuring robust implementations that maintain the real-time performance essential to Pixelocity's interactive experience.

---

*Document Version: 1.0*
*Analysis Date: 2026-03-14*
*Total Shaders Analyzed: 27*
*Scientific Concepts Applied: 10*
*Estimated Implementation Effort: 12 weeks*
