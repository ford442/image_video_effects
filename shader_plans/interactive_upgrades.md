# Interactive/Mouse-Driven Shader Upgrade Plan

## Analysis Summary

Analyzed **33 interactive shaders** focusing on smallest files (<4KB) for maximum upgrade impact potential. The current interactive shader ecosystem relies primarily on:

- **Distance-based falloff** from mouse position (90% of shaders)
- **Simple UV displacement** for distortion effects
- **Static parameter modulation** via sliders
- **Basic feedback loops** using dataTextureC for persistence

---

## Tier 1: High-Impact Upgrades (<3KB Shaders)

### 1. quantized-ripples (2,269 bytes) → "Haptic Ripple Field"
**Current:** Basic sine wave ripples with quantization

**Scientific Upgrade - Haptic Feedback Visualization:**
- **Concept:** Simulate piezoelectric haptic response patterns
- **Implementation:** 
  - Add pressure-sensitivity curves mapping mouse velocity to wave amplitude
  - Implement decay modes: `linear`, `exponential`, `critically-damped`
  - Create "touch texture" - rough/smooth surface simulation via frequency modulation
  - Add impulse response visualization showing wave packet dispersion
  
**Parameters:**
- Param1: Surface stiffness (frequency response curve)
- Param2: Damping ratio (underdamped → critically damped → overdamped)
- Param3: Haptic texture density (surface roughness)
- Param4: Impulse decay mode selector

---

### 2. echo-trace (2,827 bytes) → "Temporal Velocity Echo"
**Current:** Simple brush painting with decay

**Scientific Upgrade - Velocity-Based Motion Blur:**
- **Concept:** Optical flow-based motion trail extrapolation
- **Implementation:**
  - Store mouse velocity history in extraBuffer
  - Calculate trajectory prediction using 3-point extrapolation
  - Implement velocity-based brush deformation (stretched along movement direction)
  - Add motion blur kernel weighted by speed
  
**Parameters:**
- Param1: Prediction horizon (how far ahead to extrapolate)
- Param2: Velocity smoothing factor (Kalman-filter-like weighting)
- Param3: Trail deformation (0=circular, 1=fully stretched)
- Param4: Velocity threshold for trail activation

---

### 3. interactive-fisheye (2,836 bytes) → "Fluid Lens Dynamics"
**Current:** Static fisheye bulge at mouse

**Scientific Upgrade - Liquid Response to Impulse Forces:**
- **Concept:** Simulate surface tension and viscous fluid response
- **Implementation:**
  - Add velocity-sensitive deformation (fast movement = elongated bulge)
  - Implement spring-mass-damper system for lens surface
  - Create "splash" ripples on rapid mouse deceleration
  - Add surface tension recovery (oscillating return to equilibrium)
  
**Parameters:**
- Param1: Surface tension (spring constant k)
- Param2: Viscosity (damping coefficient c)
- Param3: Mass of fluid element (affects oscillation frequency)
- Param4: Splash threshold (impulse force for ripple generation)

---

### 4. kimi_ripple_touch (2,920 bytes) → "Multi-Touch Wave Interference"
**Current:** Single ripple source with chromatic aberration

**Scientific Upgrade - Multi-Touch Point Interpolation:**
- **Concept:** Wave superposition from multiple simultaneous sources
- **Implementation:**
  - Utilize u.ripples[50] array for multiple active touch points
  - Implement wave interference patterns (constructive/destructive)
  - Add phase-locked loop visualization for coherent sources
  - Create touch heatmap showing interaction density over time
  
**Parameters:**
- Param1: Wave coherence (random → phase-locked)
- Param2: Interference visibility (enhance fringe patterns)
- Param3: Touch history persistence
- Param4: Heatmap overlay intensity

---

### 5. velocity-field-paint (2,904 bytes) → "Navier-Stokes Brush"
**Current:** Simple velocity advection with mouse push

**Scientific Upgrade - Fluid Response to Impulse Forces:**
- **Concept:** Proper Navier-Stokes velocity field evolution
- **Implementation:**
  - Add velocity diffusion (viscosity term)
  - Implement pressure projection for divergence-free field
  - Create vorticity confinement for swirling detail preservation
  - Add density advection along velocity field
  
**Parameters:**
- Param1: Reynolds number (inertia vs viscosity balance)
- Param2: Vorticity strength (swirl preservation)
- Param3: Pressure iteration count (accuracy vs performance)
- Param4: Density diffusion rate

---

### 6. interactive-magnetic-ripple (3,164 bytes) → "Electromagnetic Field Lines"
**Current:** Simple magnetic pull with ripple

**Scientific Upgrade - Electromagnetic Field Interactions:**
- **Concept:** Visualize Lorentz force and field line topology
- **Implementation:**
  - Implement moving charge creates magnetic field (Biot-Savart)
  - Add field line tracing showing closed loops around mouse velocity
  - Create electromagnetic pulse on rapid acceleration
  - Visualize Poynting vector (energy flow direction)
  
**Parameters:**
- Param1: Charge magnitude (field strength)
- Param2: Permeability (field line density)
- Param3: Field line integration steps (trace length)
- Param4: Pulse sensitivity (acceleration threshold)

---

### 7. mirror-drag (3,135 bytes) → "Kaleidoscopic Reflection Field"
**Current:** Simple horizontal/vertical mirroring

**Scientific Upgrade - Multi-Touch Point Interpolation:**
- **Concept:** Reflection surfaces between multiple interaction points
- **Implementation:**
  - Create reflection planes between multiple mouse positions
  - Add smooth morphing between reflection configurations
  - Implement "broken mirror" effect with fracture physics
  - Create parallax depth between mirror layers
  
**Parameters:**
- Param1: Number of reflection planes
- Param2: Mirror smoothness (planar → warped)
- Param3: Fracture probability (dynamic mirror breaking)
- Param4: Depth parallax intensity

---

### 8. vortex-drag (3,169 bytes) → "Vorticity Dynamics"
**Current:** Twist + pinch with static falloff

**Scientific Upgrade - Fluid Response to Impulse Forces:**
- **Concept:** Proper vorticity transport and conservation
- **Implementation:**
  - Implement vorticity advection equation
  - Add vortex stretching along velocity gradients
  - Create vortex merger detection (two vortices combining)
  - Visualize vorticity magnitude as color-coded field
  
**Parameters:**
- Param1: Vorticity amplification (vortex stretching)
- Param2: Core size (viscous diffusion)
- Param3: Vortex merger threshold
- Param4: Field visualization mode (0=off, 1=rainbow, 2=monochrome)

---

## Tier 2: Medium-Impact Upgrades (3KB-4KB Shaders)

### 9. page-curl-interactive (3,282 bytes) → "Elastic Membrane Physics"
**Current:** Cylindrical projection with static shadow

**Scientific Upgrade - Spring-Mass-Damper Systems:**
- **Concept:** Cloth simulation with spring-mass network
- **Implementation:**
  - Model page as grid of masses connected by springs
  - Add bending resistance (angular springs between faces)
  - Implement collision detection with "finger" (mouse sphere)
  - Create realistic paper flutter from air resistance
  
**Parameters:**
- Param1: Spring stiffness (paper type: tissue→cardboard)
- Param2: Damping (air resistance)
- Param3: Bend stiffness (crease resistance)
- Param4: Flutter intensity (turbulence factor)

---

### 10. polar-warp-interactive (3,285 bytes) → "Spacetime Curvature"
**Current:** Polar coordinate distortion

**Scientific Upgrade - Gravitational Lensing:
- **Concept:** General relativity visualization
- **Implementation:**
  - Implement Schwarzschild metric approximation
  - Add gravitational time dilation (time runs slower near mouse)
  - Create Einstein ring effect at critical impact parameter
  - Visualize geodesic deviation (nearby light ray convergence)
  
**Parameters:**
- Param1: Mass of central object (curvature strength)
- Param1: Observer distance (perspective effect)
- Param3: Time dilation factor
- Param4: Show geodesic grid overlay

---

### 11. echo-ripple (3,305 bytes) → "History Wave Equation"
**Current:** Simple feedback with history blending

**Scientific Upgrade - Wave Equation Evolution:**
- **Concept:** Proper 2D wave equation solver
- **Implementation:**
  - Store previous two frames for d²u/dt² calculation
  - Implement discrete wave equation: u(t+1) = 2u(t) - u(t-1) + c²∇²u
  - Add wave reflection at boundaries
  - Create standing wave patterns from interference
  
**Parameters:**
- Param1: Wave propagation speed (c)
- Param2: Dispersion relation (frequency-dependent speed)
- Param3: Boundary condition (0=free, 1=fixed, 2=absorbing)
- Param4: Standing wave mode number

---

### 12. thermal-touch (3,399 bytes) → "Thermal Diffusion Field"
**Current:** Static heatmap with mouse heat injection

**Scientific Upgrade - Touch Heatmaps and Thermal Diffusion:**
- **Concept:** Real heat equation solver with anisotropic diffusion
- **Implementation:**
  - Implement heat equation: ∂T/∂t = α∇²T
  - Add material property variation (thermal conductivity map)
  - Create convection currents from temperature gradients
  - Add phase transition visualization (melting/freezing)
  
**Parameters:**
- Param1: Thermal diffusivity α
- Param2: Convection strength (Rayleigh number proxy)
- Param3: Phase transition temperature
- Param4: Material heterogeneity (mixed conductivity)

---

### 13. data-slicer-interactive (3,161 bytes) → "Glitch Propagation"
**Current:** Noise-based slice offset

**Scientific Upgrade - Signal Degradation Physics:**
- **Concept:** Digital signal corruption with error propagation
- **Implementation:**
  - Simulate bit-flip errors with error correction attempts
  - Add packet loss visualization with interpolation artifacts
  - Create error cascade (one error triggering more)
  - Implement compression artifact simulation
  
**Parameters:**
- Param1: Bit error rate
- Param2: Error correction strength
- Param3: Cascade probability
- Param4: Compression quality factor

---

### 14. pixel-stretch-interactive (3,479 bytes) → "Viscoelastic Deformation"
**Current:** Directional pixel duplication

**Scientific Upgrade - Non-Newtonian Fluid Response:**
- **Concept:** Shear-thinning/thickening material behavior
- **Implementation:**
  - Implement strain-rate dependent viscosity
  - Add stress relaxation (memory of deformation)
  - Create yield stress behavior (Bingham plastic)
  - Visualize stress field as color overlay
  
**Parameters:**
- Param1: Shear-thinning exponent (n < 1 = thinning, n > 1 = thickening)
- Param2: Yield stress threshold
- Param3: Stress relaxation time
- Param4: Elastic recovery fraction

---

### 15. luma-slice-interactive (3,514 bytes) → "Frequency Domain Slicing"
**Current:** Luminance-based slice offset

**Scientific Upgrade - Spectral Decomposition:**
- **Concept:** FFT-based frequency band manipulation
- **Implementation:**
  - Simulate multi-scale frequency decomposition
  - Add phase correlation between slices
  - Create spectrogram-style visualization
  - Implement filter bank response visualization
  
**Parameters:**
- Param1: Number of frequency bands
- Param2: Phase coherence between bands
- Param3: Spectral slope (pink noise → white noise)
- Param4: Band-pass filter center frequency

---

### 16. luma-melt-interactive (3,453 bytes) → "Phase Transition Dynamics"
**Current:** Vertical flow with mouse heat boost

**Scientific Upgrade - Melting Point Physics:**
- **Concept:** Solid-liquid phase transition with latent heat
- **Implementation:**
  - Track enthalpy (sensible + latent heat)
  - Implement mushy zone (partially melted region)
  - Add surface tension at liquid-air interface
  - Create Marangoni flow from surface tension gradients
  
**Parameters:**
- Param1: Latent heat of fusion
- Param2: Surface tension coefficient
- Param3: Mushy zone width
- Param4: Marangoni effect strength

---

### 17. luma-smear-interactive (4,194 bytes) → "Viscoelastic Stress Field"
**Current:** Luma threshold-based persistence

**Scientific Upgrade - Stress-Strain Relationship:**
- **Concept:** Maxwell/Kelvin-Voigt viscoelastic models
- **Implementation:**
  - Implement stress relaxation (Maxwell element)
  - Add strain creep (Kelvin-Voigt element)
  - Create stress field visualization
  - Implement nonlinear elasticity (Neo-Hookean)
  
**Parameters:**
- Param1: Elastic modulus
- Param2: Viscosity (relaxation time)
- Param3: Model blend (Maxwell ↔ Kelvin-Voigt)
- Param4: Nonlinearity exponent

---

## Tier 3: Advanced Multi-Concept Upgrades

### 18. interactive-rgb-split (3,638 bytes) → "Chromatic Aberration Optics"
**Current:** Simple RGB channel offset

**Scientific Upgrade - Lens Physics:**
- **Concept:** Real chromatic aberration from dispersion
- **Implementation:**
  - Model refractive index vs wavelength (Cauchy/Abbe)
  - Add spherical aberration correction
  - Create coma and astigmatism from off-axis rays
  - Implement depth-of-field from aperture size
  
**Parameters:**
- Param1: Abbe number (dispersion strength)
- Param2: Aperture diameter (depth of field)
- Param3: Spherical aberration coefficient
- Param4: Off-axis angle (coma/astigmatism)

---

### 19. interactive-zoom-blur (3,667 bytes) → "Camera Shutter Dynamics"
**Current:** Radial blur with sampling

**Scientific Upgrade - Exposure Physics:**
- **Concept:** Rolling shutter and exposure time effects
- **Implementation:**
  - Simulate rolling shutter readout (line-by-line capture)
  - Add motion blur from exposure time
  - Create flash synchronization effects
  - Implement electronic vs mechanical shutter artifacts
  
**Parameters:**
- Param1: Exposure time (motion blur amount)
- Param2: Rolling shutter speed
- Param3: Flash sync mode
- Param4: Mechanical shutter curtain travel

---

### 20. cursor-aura (3,674 bytes) → "Proximity Field Detection"
**Current:** Edge detection with pulsing radius

**Scientific Upgrade - Capacitive Touch Sensing:**
- **Concept:** Mutual capacitance touch sensor visualization
- **Implementation:**
  - Simulate capacitive coupling between finger and sensor
  - Add signal-to-noise ratio visualization
  - Create multi-touch capacitive map
  - Implement hover detection (pre-touch sensing)
  
**Parameters:**
- Param1: Sensing threshold
- Param2: SNR visualization mode
- Param3: Hover detection range
- Param4: Mutual vs self capacitance mode

---

### 21. interactive-ripple (4,552 bytes) → "Hydrodynamic Wave Pool"
**Current:** Wave packet with decay

**Scientific Upgrade - Full Shallow Water Equations:**
- **Concept:** Heightfield fluid with velocity field
- **Implementation:**
  - Implement shallow water equations (mass + momentum)
  - Add Coriolis force for rotating frame effects
  - Create hydraulic jump (bore) formation
  - Implement wetting/drying for shoreline
  
**Parameters:**
- Param1: Water depth (shallow vs deep water waves)
- Param2: Coriolis parameter
- Param3: Bottom friction coefficient
- Param4: Shoreline steepness

---

### 22. interactive-voronoi-lens (4,010 bytes) → "Cellular Response Field"
**Current:** Voronoi cell distortion

**Scientific Upgrade - Biological Cell Mechanics:**
- **Concept:** Cellular response to mechanical stimulus
- **Implementation:**
  - Add cell membrane elasticity
  - Implement mechanotransduction (force → signal)
  - Create cell-cell adhesion forces
  - Visualize calcium wave propagation
  
**Parameters:**
- Param1: Membrane tension
- Param2: Adhesion strength
- Param3: Signal propagation speed
- Param4: Mechanosensitivity threshold

---

### 23. interactive-voronoi-web (4,889 bytes) → "Neural Network Graph"
**Current:** Animated Voronoi edges

**Scientific Upgrade - Neural Connectivity:**
- **Concept:** Neural network with synaptic plasticity
- **Implementation:**
  - Implement Hebbian learning (cells that fire together wire together)
  - Add action potential propagation
  - Create synaptic weight visualization
  - Implement long-term potentiation/depression
  
**Parameters:**
- Param1: Synaptic learning rate
- Param2: Action potential speed
- Param3: Plasticity threshold
- Param4: Network topology (random → small-world)

---

### 24. interactive-glitch-brush (3,593 bytes) → "Data Corruption Physics"
**Current:** Block noise with color split

**Scientific Upgrade - Information Theory:**
- **Concept:** Entropy and information loss visualization
- **Implementation:**
  - Simulate Shannon entropy changes
  - Add error detection/correction codes
  - Create information cascade failure
  - Visualize data compression artifacts
  
**Parameters:**
- Param1: Entropy injection rate
- Param2: Error correction strength
- Param3: Cascade failure probability
- Param4: Compression ratio

---

### 25. mouse-gravity (4,338 bytes) → "General Relativity Visualization"
**Current:** Exponential distortion falloff

**Scientific Upgrade - Accurate Gravitational Physics:**
- **Concept:** Schwarzschild metric with time dilation
- **Implementation:**
  - Add proper photon sphere visualization
  - Implement frame dragging (rotating mass)
  - Create gravitational redshift
  - Add accretion disk physics
  
**Parameters:**
- Param1: Black hole spin (Kerr parameter)
- Param2: Accretion rate
- Param3: Redshift intensity
- Param4: Photon sphere visibility

---

## Implementation Priority Matrix

| Shader | Scientific Concept | Impact | Complexity | Priority |
|--------|-------------------|--------|------------|----------|
| velocity-field-paint | Fluid Dynamics | High | Medium | 1 |
| thermal-touch | Thermal Diffusion | High | Medium | 2 |
| interactive-fisheye | Spring-Mass-Damper | High | Low | 3 |
| quantized-ripples | Haptic Visualization | Medium | Low | 4 |
| vortex-drag | Vorticity Dynamics | High | Medium | 5 |
| echo-trace | Velocity Motion Blur | Medium | Low | 6 |
| kimi_ripple_touch | Multi-Touch Interference | Medium | Low | 7 |
| luma-melt-interactive | Phase Transitions | High | Medium | 8 |
| page-curl-interactive | Elastic Membrane | High | High | 9 |
| interactive-magnetic-ripple | EM Fields | Medium | Medium | 10 |

---

## Technical Implementation Notes

### DataTexture Usage for Scientific State

```wgsl
// dataTextureA (RG) = velocity field (vx, vy)
// dataTextureA (BA) = additional state (pressure, temperature)
// dataTextureC (RG) = previous velocity (for time derivatives)
// dataTextureC (BA) = scalar fields (density, vorticity)
// extraBuffer[0-49] = mouse position history for trajectory
// extraBuffer[50-99] = velocity magnitude history
```

### extraBuffer Layout for Advanced Simulations

```wgsl
// Multi-touch tracking
// extraBuffer[0..49] = ripple positions x
// extraBuffer[50..99] = ripple positions y
// extraBuffer[100..149] = start times
// extraBuffer[150..199] = pressure/force values

// Velocity history for prediction
// extraBuffer[200..249] = mouse velocity x history
// extraBuffer[250..299] = mouse velocity y history
```

### Recommended New Parameters Structure

All upgraded shaders should expose:
- **Param1:** Physical coefficient (diffusivity, stiffness, etc.)
- **Param2:** Temporal parameter (decay, relaxation, timescale)
- **Param3:** Spatial parameter (scale, wavelength, range)
- **Param4:** Mode/behavior selector (discrete modes)

---

## Artistic Vision

These upgrades transform simple mouse effects into **physics-based playgrounds** where:
- Every interaction has consequences that evolve over time
- Users intuitively learn physical concepts through exploration
- Visual feedback is scientifically grounded yet aesthetically compelling
- Small parameter changes create dramatically different emergent behaviors

**Key Design Philosophy:** The scientific model should enhance, not constrain, the artistic expression. Each shader becomes a window into a micro-universe with its own consistent physical laws.
