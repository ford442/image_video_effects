# Generative Shader Upgrade Plan

## Executive Summary

This document analyzes 49+ generative/procedural shaders in the Pixelocity project and identifies upgrade opportunities, focusing on "easy wins" for shaders under 4KB. The goal is to enhance visual complexity by applying established scientific/mathematical concepts from procedural graphics.

---

## Shader Inventory by Size

### Tier 1: Micro Shaders (<2KB) - Easy Upgrade Wins

| Shader | Size | Current Concept | Upgrade Path |
|--------|------|-----------------|--------------|
| `gen_orb` | 1,402 bytes | Simple glow orb | **Strange attractor particles** - Replace static orb with particle trails from Lorenz/Rössler attractors |
| `gen_grokcf_interference` | 1,535 bytes | Wave interference | **Modal synthesis cymatics** - Multiple resonant modes with Chladni plate patterns |
| `gen_grid` | 1,594 bytes | Animated grid | **Domain warped grid** - Apply FBM distortion to UV space for organic grid |
| `gen_grokcf_voronoi` | 1,630 bytes | Basic Voronoi | **Worley noise FBM** - Layer multiple octaves, add edge detection |
| `gen_grok41_plasma` | 1,648 bytes | Sine plasma | **Spherical harmonics** - Project onto sphere, use SH coefficients |
| `galaxy` | 1,682 bytes | Fragment shader | **Deprecated** - Use `galaxy-compute` instead |
| `gen_trails` | 1,878 bytes | Mouse trails | **Particle flocking** - Boids algorithm with separation/alignment/cohesion |
| `gen_grok41_mandelbrot` | 1,883 bytes | Basic Mandelbrot | **Buddhabrot** - Accumulate escaped orbits for nebula-like effect |
| `gen_julia_set` | 2,099 bytes | Basic Julia | **Newton fractal** - Convergence basins for z³-1 roots |

### Tier 2: Small Shaders (2-4KB) - Medium Complexity

| Shader | Size | Current Concept | Upgrade Path |
|--------|------|-----------------|--------------|
| `gen_grok4_life` | 2,165 bytes | Conway's Life | **Smooth Life** - Continuous states with bell-shaped neighborhood functions |
| `gen_grok4_perlin` | 2,349 bytes | Perlin terrain | **Erosion simulation** - Thermal and hydraulic erosion passes |
| `gen_psychedelic_spiral` | 2,486 bytes | Spiral pattern | **Spirograph epicycles** - Multiple nested rotating circles |
| `gen_wave_equation` | 2,654 bytes | Wave physics | **Klein-Gordon** - Add nonlinear term for solitons |
| `gen-raptor-mini` | 2,746 bytes | Agent particles | **Slime mold** - Physarum-style chemotaxis simulation |
| `galaxy-compute` | 2,984 bytes | Basic compute | **N-body gravity** - Particle system with mutual gravitational attraction |
| `gen_reaction_diffusion` | 3,184 bytes | Gray-Scott | **Turing morphogenesis** - Multiple activator-inhibitor pairs |
| `gen_cyclic_automaton` | 3,202 bytes | Cyclic CA | **Greenberg-Hastings** - Excitable media with refractory states |
| `gen_fluffy_raincloud` | 3,812 bytes | Particle cloud | **Navier-Stokes fluid** - Velocity-pressure solve for realistic clouds |
| `gen_capabilities` | 3,490 bytes | Debug overlay | **Oscilloscope vectors** - Procedural vector display simulation |
| `gen_rainbow_smoke` | 4,088 bytes | Curl noise smoke | **Vorticity confinement** - Better turbulence preservation |
| `gen-cosmic-web-filament` | 3,908 bytes | Voronoi filaments | **Delaunay triangulation** - Cosmic web with proper topology |
| `gen-crystal-caverns` | 4,060 bytes | Raymarched caves | **IFS fractals** - Iterated function systems for crystals |

### Tier 3: Medium Shaders (4-8KB) - Advanced Upgrades

| Shader | Size | Current Concept | Upgrade Path |
|--------|------|-----------------|--------------|
| `gen_kimi_nebula` | 4,371 bytes | FBM nebula | **Dust extinction** - Rayleigh/Mie scattering through density field |
| `gen-lenia-2` | 4,377 bytes | Multi-species Lenia | **Continuous Lenia** - Smooth kernel convolution on GPU |
| `gen_kimi_crystal` | 4,682 bytes | Hex grid crystals | **Quasicrystals** - Penrose tiling with inflation rules |
| `gen-fractal-clockwork` | 5,259 bytes | Gear raymarching | **L-system gears** - Recursive gear train generation |
| `gen-magnetic-ferrofluid` | 5,710 bytes | Ferrofluid sim | **Maxwell stress tensor** - Proper magnetic field visualization |
| `gen-quantum-mycelium` | 6,418 bytes | Network growth | **Dijkstra pathfinding** - Optimal transport networks |
| `gen-stellar-web-loom` | 6,474 bytes | Star connections | **Delaunay/Voronoi dual** - Proper constellation topology |
| `gen-silica-tsunami` | 6,847 bytes | Wave simulation | **Burgers equation** - Shock wave formation |
| `gen-hyper-labyrinth` | 7,170 bytes | Maze generator | **Hilbert curve** - Space-filling labyrinth |
| `gen-fractured-monolith` | 7,494 bytes | Fracture patterns | **Peridynamics** - Material point failure simulation |
| `gen-micro-cosmos` | 7,651 bytes | Microscopic view | **Brownian motion** - Stochastic particle dynamics |
| `gen-prismatic-bismuth-lattice` | 7,846 bytes | Bismuth crystals | **Hopper growth** - Crystallographic preferred growth |
| `gen-quantum-neural-lace` | 8,015 bytes | Network | **Graph Laplacian** - Spectral graph theory visualization |

### Tier 4: Large Shaders (8KB+) - Optimization Focus

| Shader | Size | Current Concept | Upgrade Path |
|--------|------|-----------------|--------------|
| `gen-neuro-cosmos` | 8,215 bytes | Neural network | **Hopfield network** - Energy minimization dynamics |
| `gen-bismuth-crystal-citadel` | 8,700 bytes | Crystal city | **Diffusion-limited aggregation** - DLA for organic structures |
| `gen-holographic-data-core` | 8,715 bytes | Holographic display | **Pepper's ghost** - Proper holographic optics |
| `gen-cyber-terminal` | 9,105 bytes | Terminal UI | **CRT emulation** - Full phosphor decay + scanlines |
| `gen-brutalist-monument` | 9,182 bytes | Architecture | **L-system buildings** - Procedural brutalist grammar |
| `gen-alien-flora` | 9,405 bytes | Alien plants | **Space colonization** - Meandering growth patterns |
| `gen-ethereal-anemone-bloom` | 9,413 bytes | Anemone | **Verlet integration** - Soft body dynamics |
| `gen-isometric-city` | 10,940 bytes | City generation | **Wave function collapse** - Tiled city generation |
| `gen-bioluminescent-abyss` | 11,082 bytes | Deep sea | **Reaction-diffusion skin** - Pattern formation on creatures |
| `gen-celestial-forge` | 11,739 bytes | Star forge | **Accretion disk** - Angular momentum physics |
| `gen-biomechanical-hive` | 12,013 bytes | Hive structure | **Voronoi foams** - Biologically-accurate cell structures |
| `gen-art-deco-sky` | 13,728 bytes | Art deco | **Sunburst geometry** - Radial tessellation patterns |
| `gen-chronos-labyrinth` | 14,080 bytes | Time labyrinth | **Nonlinear time** - Causal loop visualization |

---

## Scientific Concepts Library

### 1. Strange Attractors (for `gen_orb` upgrade)

**Lorenz System:**
```
dx/dt = σ(y - x)
dy/dt = x(ρ - z) - y
dz/dt = xy - βz
σ=10, ρ=28, β=8/3
```

**Aizawa Attractor:**
```
dx/dt = (z - b)x - dy
dy/dt = (z - b)y + dx
dz/dt = c + az - z³/3 - (x² + y²)(1 + ez) + fzx³
```

**Implementation approach:**
- Generate 1000+ particles
- Integrate with RK4 (Runge-Kutta 4th order)
- Render as glowing trails with additive blending
- Mouse attraction to control viewing angle

---

### 2. Reaction-Diffusion Systems (for `gen_reaction_diffusion` enhancements)

**Gray-Scott (already implemented):**
- Feed rate: 0.02-0.08
- Kill rate: 0.05-0.07

**Turing Patterns:**
```
∂u/∂t = Du∇²u + f(u,v)
∂v/∂t = Dv∇²v + g(u,v)
```

**Fitzhugh-Nagumo (excitable media):**
- Action potential waves
- Similar to `gen_cyclic_automaton`

---

### 3. Noise Functions (for `gen_grok4_perlin` upgrade)

**Current:** Perlin noise with FBM

**Upgrades:**
- **Simplex noise** - Lower computational complexity
- **Wavelet noise** - Band-limited, no aliasing
- **Gabor noise** - Spot-based procedural texture
- **Anisotropic noise** - Directional features

**Domain Warping:**
```
F(p) = f(p + f(p*2)*0.5 + f(p*4)*0.25)
```
Creates organic, flowing patterns from regular noise.

---

### 4. Cellular Automata (for `gen_grok4_life` upgrade)

**Current:** Conway's Game of Life (binary)

**Smooth Life:**
- Continuous state [0,1]
- Bell-shaped neighborhood function
- Complex life-like behaviors emerge naturally

**Lenia:**
- Kernel-based convolution
- Multiple species support
- Already implemented in `gen-lenia-2`

**Brian's Brain:**
- Excitable media
- Ready → Firing → Refractory cycle

---

### 5. Fractals (for `gen_grok41_mandelbrot` upgrade)

**Buddhabrot:**
- Track escaped orbits
- Accumulate density in histogram
- Incredibly beautiful nebula-like result

**Newton Fractal:**
- Roots of z³ - 1 = 0
- Different colors for different basins
- Smooth coloring by iteration count

**Burning Ship:**
- abs(z) in iteration
- Distinct "burning" appearance

**Phoenix:**
- Uses previous iteration value
- Creates spiral structures

---

### 6. Voronoi/Worley Noise (for `gen_grokcf_voronoi` upgrade)

**Current:** Basic Voronoi (distance to closest point)

**Upgrades:**
- **F2-F1** - Difference between 2nd and 1st nearest
- **Cell ID coloring** - Random color per cell
- **Crackle pattern** - 1/(F2-F1)
- **Voronoi worms** - Following edges

---

### 7. L-Systems (for new organic shaders)

**Turtle graphics:**
- F = move forward
- + = turn left
- - = turn right
- [ = save position
- ] = restore position

**Example - Dragon Curve:**
```
Axiom: FX
Rules: X → X+YF+, Y → −FX−Y
Angle: 90°
```

**Implementation:**
- Pre-compute L-system string on CPU
- Render in shader with line segments
- Add glow and bloom

---

### 8. Fluid Dynamics (for `gen_fluffy_raincloud` upgrade)

**Navier-Stokes:**
```
∂u/∂t = -(u·∇)u - ∇p/ρ + ν∇²u + f
∇·u = 0  (incompressibility)
```

**Curl noise:**
- `u = ∇ × ψ` where ψ is potential field
- Automatically divergence-free
- Already partially implemented in `gen_rainbow_smoke`

**Vorticity confinement:**
- Preserves small-scale turbulence
- Critical for realistic smoke

---

### 9. Superformula (for `gen_psychedelic_spiral` upgrade)

Generalization of superellipse:
```
r(φ) = (|cos(mφ/4)/a|^n2 + |sin(mφ/4)/b|^n3)^(-1/n1)
```

Creates complex organic shapes:
- Shells
- Flowers
- Stars
- Abstract forms

---

### 10. Physarum / Slime Mold (for `gen-raptor-mini` upgrade)

**Algorithm:**
1. Agents deposit trail
2. Agents sense trail ahead
3. Agents turn toward strongest trail
4. Trail diffuses and evaporates

**Behavior:**
- Forms efficient networks
- Finds shortest paths
- Creates organic patterns

---

## Priority Upgrade Recommendations

### Phase 1: Quick Wins (<4KB shaders)

1. **`gen_orb` → Lorenz Attractor**
   - Replace single orb with particle system
   - ~50 lines additional code
   - Dramatic visual improvement

2. **`gen_grid` → Domain Warped Grid**
   - Add FBM displacement to UVs
   - ~10 lines additional code
   - Transforms rigid grid to organic mesh

3. **`gen_grok41_mandelbrot` → Buddhabrot**
   - Accumulate orbit histogram
   - ~30 lines additional code
   - Creates beautiful nebula imagery

4. **`gen_grokcf_voronoi` → Worley FBM**
   - Layer 3-4 octaves of Worley noise
   - ~15 lines additional code
   - Rich, detailed textures

5. **`gen_trails` → Boids Flocking**
   - Implement separation/alignment/cohesion
   - ~40 lines additional code
   - Emergent swarm behavior

### Phase 2: Simulation Improvements (4-8KB shaders)

1. **`gen_wave_equation` → Klein-Gordon Solitons**
2. **`gen_reaction_diffusion` → Multi-species Turing**
3. **`gen_fluffy_raincloud` → Navier-Stokes Clouds**
4. **`gen_crystal_caverns` → IFS Fractals**

### Phase 3: Advanced Features (8KB+ shaders)

1. **`gen-isometric-city` → Wave Function Collapse**
2. **`gen-bioluminescent-abyss` → RD on Creatures**
3. **`gen-celestial-forge` → Accretion Disk Physics**

---

## Implementation Notes

### Shader Templates to Create

1. **Attractor Template** - Particle trail rendering
2. **FBM Warp Template** - Domain distortion patterns
3. **Multi-pass Sim Template** - CA/RD/Fluid simulations
4. **Raymarch Template** - SDF-based 3D scenes

### Common Utilities Needed

```wgsl
// Noise functions
fn hash2(p: vec2<f32>) -> vec2<f32>
fn hash3(p: vec3<f32>) -> vec3<f32>
fn noise(p: vec3<f32>) -> f32
fn fbm(p: vec3<f32>, octaves: i32) -> f32

// SDF primitives
fn sdSphere(p: vec3<f32>, r: f32) -> f32
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32
fn sdHexagon(p: vec2<f32>, r: f32) -> f32

// Color utilities
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32>
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32>
```

### Performance Considerations

- Keep workgroup_size at (8, 8, 1)
- Minimize texture samples in loops
- Use `select()` instead of `if` where possible
- Precompute constants outside loops
- Consider multi-pass for complex simulations

---

## Success Metrics

- **Visual Complexity:** Shaders should show more interesting patterns
- **Scientific Accuracy:** Implementations should reflect real phenomena
- **Performance:** Maintain 60fps at 1080p
- **Code Quality:** Consistent style, well-commented
- **User Engagement:** Mouse interaction should feel responsive

---

## Appendix: Reference Implementations

### Inigo Quilez Resources
- iq/textures - Noise functions
- iq/raymarching - SDF techniques
- iq/fractals - Mandelbrot/Julia variants

### The Book of Shaders
- Cellular noise (Worley/Voronoi)
- Fractal Brownian Motion
- Reaction-Diffusion

### ShaderToy Examples
- "Attractors" by guil
- "Physarum" by saxond
- "Navier-Stokes" by ollj
- "Buddhabrot" by eiffie

---

*Document Version: 1.0*
*Analysis Date: 2026-03-14*
*Total Shaders Analyzed: 49+*
