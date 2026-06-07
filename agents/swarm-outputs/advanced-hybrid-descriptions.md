# Advanced Hybrid Shader Descriptions
## Created by Agent 3B - Advanced Hybrid Creator
## Date: 2026-03-22

---

## Part 1: Complex Multi-Technique Shaders (10)

### 1. Hyper Tensor Fluid
**Category:** Simulation  
**Complexity:** Very High

Fluid flows according to image structure via tensor eigendecomposition. This shader combines:
- **Tensor field mathematics**: Structure tensor calculated from image gradients
- **Navier-Stokes dynamics**: Velocity advection with viscosity
- **FBM turbulence**: Multi-octave noise for organic motion
- **Depth-aware rendering**: Depth affects flow intensity

**Visual Effect:** Edges in the image create barriers to flow while smooth areas allow fluid movement. The result is a liquid distortion that follows the image's structure, with iridescent highlights along flow lines.

**Parameter Guide:**
- X: Tensor strength - how much image structure affects flow
- Y: Viscosity - fluid thickness/resistance
- Z: Turbulence - FBM noise amount
- W: Advection speed - flow velocity

---

### 2. Neural Raymarcher
**Category:** Generative  
**Complexity:** Very High

Raymarched neural network with activation visualization. Combines:
- **SDF raymarching**: 3D signed distance field rendering
- **Neural patterns**: tanh, ReLU, sigmoid activation functions
- **Volumetric glow**: Post-process glow effect
- **Animated connections**: Weights visualized as connection thickness

**Visual Effect:** A glowing 3D neural network structure floating in space, with neurons pulsing based on their activation functions. Connections between neurons animate with simulated weight values.

**Parameter Guide:**
- X: Network depth - number of layers
- Y: Activation visualization - how much activations affect color
- Z: Glow intensity - volumetric glow amount
- W: Camera rotation - orbit around the network

---

### 3. Chromatic Reaction-Diffusion
**Category:** Artistic  
**Complexity:** High

Multi-channel Gray-Scott reaction-diffusion with chromatic separation. Features:
- **Separate feed/kill rates**: Each RGB channel has independent parameters
- **Chromatic aberration**: RGB channels displaced based on gradients
- **Mouse interaction**: Inject chemicals at cursor position

**Visual Effect:** Organic Turing patterns where each color channel evolves independently, creating chromatic fringes at pattern boundaries. The patterns resemble chemical reactions on photographic paper.

**Parameter Guide:**
- X: Red feed rate - pattern density for red channel
- Y: Green feed rate - pattern density for green channel
- Z: Blue feed rate - pattern density for blue channel
- W: Chromatic separation - RGB channel displacement

---

### 4. Audio Voronoi Displacement
**Category:** Distortion  
**Complexity:** High

Audio-reactive Voronoi cells that displace the image. Combines:
- **Voronoi tessellation**: Cell-based decomposition
- **Audio FFT simulation**: Bass/mid/treble bands affect cells
- **Displacement mapping**: Audio drives cell movement
- **Frequency-based coloring**: Cells colored by dominant frequency

**Visual Effect:** The image fractures into cells that pulse and move with simulated music. Each cell is tinted by the frequency band that affects it most.

**Parameter Guide:**
- X: Cell count - number of Voronoi cells
- Y: Audio reactivity - how much audio affects cells
- Z: Displacement strength - cell movement amount
- W: Color intensity - frequency coloring strength

---

### 5. Fractal Boids Field
**Category:** Simulation  
**Complexity:** High

Flocking behavior on a fractal vector field. Features:
- **Reynolds boids**: Separation, alignment, cohesion rules
- **Fractal flow field**: Domain-warped FBM currents
- **Trail rendering**: GPU particle trails
- **Flow visualization**: Vector field display

**Visual Effect:** Swarms of particles flowing through organic fractal currents, leaving glowing trails. The particles flock together while following the underlying flow field.

**Parameter Guide:**
- X: Boid count - number of simulated particles
- Y: Flow field strength - influence of fractal currents
- Z: Trail persistence - how long trails last
- W: Separation distance - personal space of boids

---

### 6. Holographic Interferometry
**Category:** Generative  
**Complexity:** High

Simulated hologram with interference fringe patterns. Combines:
- **Interference mathematics**: Constructive/destructive patterns
- **Phase-based coloring**: Rainbow hologram colors
- **Speckle noise**: Laser coherence simulation
- **Depth parallax**: View-dependent reconstruction

**Visual Effect:** Rainbow interference fringes across the image with speckled laser light. Creates a convincing holographic reconstruction effect.

**Parameter Guide:**
- X: Fringe density - number of interference fringes
- Y: Coherence - speckle pattern size
- Z: Reconstruction angle - hologram viewing angle
- W: Saturation - color intensity

---

### 7. Gravitational Lensing
**Category:** Distortion  
**Complexity:** Very High

General relativistic light bending around black hole. Features:
- **Schwarzschild metric**: Curved spacetime simulation
- **Geodesic raytracing**: Light path bending
- **Accretion disk**: Glowing matter around black hole
- **Gravitational redshift**: Color shifts near horizon

**Visual Effect:** Background stars and image content distorted around a black hole, creating an Einstein ring. The accretion disk glows with Doppler beaming effects.

**Parameter Guide:**
- X: Black hole mass - strength of gravity
- Y: Accretion brightness - disk glow intensity
- Z: Camera orbit - viewing angle
- W: Redshift - gravitational color shift intensity

---

### 8. Cellular Automata 3D
**Category:** Generative  
**Complexity:** Very High

3D Game of Life rendered with volume raymarching. Features:
- **26-neighbor CA**: 3D cellular automata rules
- **Birth 4-5, Survival 5-6**: Life-like rules in 3D
- **Volume rendering**: Raymarch through cell volume
- **Transfer function**: Cell age determines color

**Visual Effect:** Glowing 3D structures that evolve frame-by-frame. Young cells are red, maturing through green/blue to purple.

**Parameter Guide:**
- X: Evolution speed - CA update rate
- Y: Initial density - starting cell population
- Z: Color cycling - hue shift speed
- W: Camera rotation - view angle

---

### 9. Spectral Flow Sorting
**Category:** Distortion  
**Complexity:** High

Optical flow-based pixel sorting with spectral analysis. Combines:
- **Optical flow**: Motion estimation between frames
- **Pixel sorting**: Sort along flow lines
- **Frequency analysis**: FFT-inspired local frequency detection
- **Directional coloring**: Flow direction determines hue

**Visual Effect:** Pixels flow and sort along motion vectors, with colors shifting based on spatial frequencies. Creates a glitch-art aesthetic with organic motion.

**Parameter Guide:**
- X: Flow sensitivity - motion detection threshold
- Y: Sort threshold - pixel sorting cutoff
- Z: Frequency influence - spectral coloring amount
- W: Smoothing - temporal blend factor

---

### 10. Multi-Fractal Compositor
**Category:** Generative  
**Complexity:** High

Smooth morphing between multiple fractal types. Features:
- **Mandelbrot set**: Classic z²+c iteration
- **Julia set**: Fixed c, varying z
- **Burning Ship**: Absolute value variant
- **Newton fractal**: Root-finding visualization

**Visual Effect:** Morphing fractals that smoothly transition between types. Domain warping adds organic feel to the mathematical structures.

**Parameter Guide:**
- X: Zoom level - magnification into fractal
- Y: Iterations - calculation depth
- Z: Domain warp - organic distortion amount
- W: Fractal blend - type transition control

---

## Part 2: Multi-Pass Simulation Shaders (8)

### 11. Sim: Fluid Feedback Field
**Category:** Simulation  
**Type:** Multi-pass (3 passes)

Navier-Stokes fluid simulation with feedback trails:
- **Pass 1**: Velocity advection with curl noise
- **Pass 2**: Density advection through velocity field
- **Pass 3**: Composite with glow and color grading

**Visual Effect:** Glowing fluid that swirls, mixes, and leaves trails - like ink in water with light inside.

**Performance Target:** 45-60 FPS

---

### 12. Sim: Heat Haze Field
**Category:** Distortion  
**Type:** Single-pass with feedback

Temperature simulation with convection:
- Temperature field diffusion
- Convection current calculation
- Refraction based on temperature gradient

**Visual Effect:** Desert mirage effect with rising heat patterns. Hot areas shimmer with distortion while cooler areas remain clearer.

**Performance Target:** 60 FPS

---

### 13. Sim: Sand Dunes
**Category:** Simulation  
**Type:** Single-pass with feedback

Falling sand cellular automata:
- Grid-based sand physics
- Angle of repose piling
- Wind erosion simulation

**Visual Effect:** Dynamic sand dunes that shift and evolve. Sand falls, piles, and is sculpted by wind.

**Performance Target:** 60 FPS

---

### 14. Sim: Ink Diffusion
**Category:** Artistic  
**Type:** Single-pass with feedback

Multi-channel Gray-Scott reaction-diffusion:
- Each RGB = separate chemical
- Wolfram-validated parameters
- Paper texture affects diffusion

**Visual Effect:** Ink drops spreading on wet paper. Deep blacks, blues, and reds blend organically.

**Performance Target:** 60 FPS

---

### 15. Sim: Smoke Trails
**Category:** Simulation  
**Type:** Single-pass with feedback

Volumetric smoke with vorticity:
- Simplified fluid dynamics
- Buoyancy-driven motion
- Temperature-based rendering

**Visual Effect:** Billowing smoke rising with natural turbulence. Gray smoke with fire-source glow at bottom.

**Performance Target:** 60 FPS

---

### 16. Sim: Slime Mold Growth
**Category:** Simulation  
**Type:** Single-pass with feedback

Physarum-style agent simulation:
- 1000s of agents depositing trails
- Sensor-based steering (left/center/right)
- Trail following behavior

**Visual Effect:** Branching network of glowing cyan trails exploring space. Organic pathfinding and network optimization.

**Performance Target:** 30-45 FPS

---

### 17. Sim: Volumetric Fake
**Category:** Lighting Effects  
**Type:** Single-pass

Approximate god rays without raymarching:
- Radial blur from light source
- Depth-based density
- Dust particle simulation

**Visual Effect:** Light beams through dusty air, volumetric god rays. Warm shafts through cool shadows.

**Performance Target:** 60 FPS

---

### 18. Sim: Decay System
**Category:** Artistic  
**Type:** Single-pass with feedback

Multi-layer corrosion simulation:
- Decay from edges inward
- Material-dependent decay rates
- Protection painting via mouse

**Visual Effect:** Image appears to corrode, rust, or decay over time. Vibrant colors fade through corroded tones to dark.

**Performance Target:** 60 FPS

---

## Summary Statistics

| Category | Count |
|----------|-------|
| Complex Multi-Technique | 10 |
| Multi-Pass Simulations | 8 |
| **Total** | **18** |

| Performance Target | Count |
|-------------------|-------|
| 60 FPS | 12 |
| 45-60 FPS | 4 |
| 30-45 FPS | 2 |

---

*Documentation created by Agent 3B - Advanced Hybrid Creator*
