# Generative Shader Upgrade Swarm Analysis

> **Generated**: 2026-04-12  
> **Target**: 8 smallest generative shaders  
> **Line Count Range**: 83-113 lines → Target: 150-180 lines

---

## Executive Summary

Analyzed the **8 smallest generative shaders** (83-113 lines) and created detailed upgrade plans to expand them to **150-180 lines** with:
- Advanced mathematical functions (SDFs, FBM, reaction-diffusion)
- Enhanced RGBA channel encoding
- Physics simulations (orbital mechanics, pendulums)
- Multi-pass temporal effects

---

## Shader Upgrade Matrix

| # | Shader | Current | Target | +Lines | Complexity |
|---|--------|---------|--------|--------|------------|
| 1 | gen-raptor-mini | 84 | 170 | +86 | 🟢 Medium |
| 2 | gen-xeno-botanical | 91 | 165 | +74 | 🟡 Medium-High |
| 3 | gen-astro-chrono-orrery | 104 | 170 | +66 | 🔴 High |
| 4 | gen-cosmic-web-filament | 106 | 165 | +59 | 🔴 High |
| 5 | gen-lenia-2 | 108 | 155 | +47 | 🟡 Medium-High |
| 6 | gen-vitreous-chandelier | 109 | 165 | +56 | 🔴 High |
| 7 | gen-kinetic-brutalist | 111 | 170 | +59 | 🔴 High |
| 8 | gen-crystal-caverns | 113 | 160 | +47 | 🟡 Medium-High |

---

## Detailed Upgrade Plans

### 1. gen-raptor-mini.wgsl (84 lines)

**Current**: Simple cellular noise with hash-based raptor simulation

**5 Expansion Ideas**:
1. **FBM-Enhanced Territorial Marking** - Multi-octave noise for organic scent trails
2. **SDF-Based Raptor Anatomy** - Articulated shapes (capsule + triangle) for predator bodies
3. **Reaction-Diffusion Prey Field** - Gray-Scott RD for prey that raptors hunt
4. **Multi-Pass Particle Swarm History** - dataTexture for temporal persistence
5. **Voronoi Territorial Partitioning** - Pack territory visualization

**New Functions**:
```wgsl
fn fbm(p: vec2<f32>, octaves: i32) -> f32
fn sdCapsule(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, r: f32) -> f32
fn voronoi(uv: vec2<f32>, t: f32) -> vec2<f32>
fn accumulateScent(uv: vec2<f32>, raptorPos: vec2<f32>, strength: f32) -> f32
```

**RGBA Enhancement**:
- R: Territorial intensity + rage pulse
- G: Scent trail concentration (temporal feedback)
- B: Voronoi cell ID-based hue
- A: Distance-based falloff + motion blur

---

### 2. gen-xeno-botanical-synth-flora.wgsl (91 lines)

**Current**: Botanical pattern with branch generation

**5 Expansion Ideas**:
1. **L-System Fractal Branching** - String-rewriting for realistic plant structure
2. **Reaction-Diffusion Morphogenesis** - Turing patterns for leaf venation
3. **FBM Displacement Mapping** - Domain warping for bark texture
4. **Multi-Pass Growth Simulation** - dataTexture for iterative growth
5. **SDF Leaf Shapes** - Parameterized leaf morphology

**New Functions**:
```wgsl
fn fbm(p: vec2<f32>, octaves: i32) -> f32
fn branchDensity(uv: vec2<f32>, angle: f32, complexity: f32, t: f32) -> f32
fn sdLeaf(p: vec2<f32>, len: f32, wid: f32) -> f32
fn turingPattern(uv: vec2<f32>, t: f32) -> f32
```

**RGBA Enhancement**:
- R: Growth maturity + vascular pattern
- G: Chlorophyll density + nutrient flow
- B: Bioluminescence + cyanobacteria tint
- A: Layered depth + transpiration thickness

---

### 3. gen-astro-kinetic-chrono-orrery.wgsl (104 lines)

**Current**: Ray-marched torus rings with mouse rotation

**5 Expansion Ideas**:
1. **Keplerian Orbital Mechanics** - Proper orbital elements (a, e, i, ω)
2. **Multi-Body Gravitational Singularity** - Schwarzschild-inspired core with accretion disk
3. **Hierarchical Moon Systems** - Nested orbital systems with resonance
4. **Spiral Galaxy Density Profile** - Exponential disk + logarithmic spiral arms
5. **Particle Dust/Asteroid Belt** - Procedural grain simulation

**New Functions**:
```wgsl
fn keplerOrbit(theta: f32, a: f32, e: f32) -> f32
fn blackbodyColor(temp: f32) -> vec3<f32>
fn accretionDiskDensity(r: f32, theta: f32, t: f32) -> f32
fn spiralArmOffset(r: f32, armIndex: f32, numArms: f32, t: f32) -> vec2<f32>
fn particlePosition(id: f32, t: f32, innerR: f32, outerR: f32) -> vec3<f32>
```

**RGBA Enhancement**:
- R: Temperature-based (blackbody radiation)
- G: Metallic ring coloring
- B: Particle sparkle intensity
- A: Volumetric density + atmospheric effects

---

### 4. gen-cosmic-web-filament.wgsl (106 lines)

**Current**: 3D Voronoi-based cosmic web

**5 Expansion Ideas**:
1. **Multi-Fractal Structure** - Multiplicative cascade for hierarchy
2. **Spiral Galaxy Projection** - Disk plane with spiral perturbation
3. **Particle/Grain System** - Stellar populations with color-magnitude
4. **Volumetric Light Scattering** - Mie phase function god rays
5. **Temporal Evolution** - Zel'dovich approximation for structure formation

**New Functions**:
```wgsl
fn multifractalNoise(p: vec3<f32>, octaves: i32, H: f32) -> f32
fn ridgedVoronoi(p: vec3<f32>, octaves: i32) -> f32
fn spiralWarp(p: vec3<f32>, arms: f32, pitch: f32, strength: f32) -> vec3<f32>
fn stellarColor(age: f32, metallicity: f32) -> vec3<f32>
fn volumetricGlow(p: vec3<f32>, lightPos: vec3<f32>, density: f32) -> f32
```

**RGBA Enhancement**:
- R: Structure density
- G: Temperature gradient (nodes vs filaments)
- B: Stellar population color
- A: Volumetric transparency

---

### 5. gen-lenia-2.wgsl (108 lines)

**Current**: Multi-species smooth life (4 kernels)

**5 Expansion Ideas**:
1. **Extended Kernel Shapes** - Gaussian, exponential, Mexican hat, polynomial
2. **Species DNA Encoding** - Species type, energy, age, cooldown in RGBA
3. **8-Sample Radial Kernel** - 45° interval sampling with distance weighting
4. **Species Interaction Matrix** - 4×4 predator-prey relationships
5. **Visual Species Signature** - HSV-based species visualization

**New Functions**:
```wgsl
fn kernel_gaussian(x: f32, sigma: f32) -> f32
fn kernel_mexican_hat(x: f32, sigma: f32) -> f32
fn kernel_sample_8(uv: vec2<f32>, radius: f32, kernel_type: i32) -> vec4<f32>
fn species_interaction(species_a: f32, species_b: f32) -> f32
fn species_to_color(dna: SpeciesDNA) -> vec3<f32>
```

**RGBA Enhancement**:
- R: Species ID (0-1 → 4 species)
- G: Energy / Health
- B: Age / Generation
- A: Reproduction cooldown

---

### 6. gen-vitreous-chrono-chandelier.wgsl (109 lines)

**Current**: Ray-marched octahedron chandelier

**5 Expansion Ideas**:
1. **Multiple SDF Primitives** - Tori, boxes, spheres, rounded shapes
2. **Pendulum Physics** - d²θ/dt² = -(g/L)sin(θ) with damping
3. **Caustics and Refraction** - Fresnel equations, Snell's law
4. **Hierarchical Structure** - Central stem + arms + crystals
5. **Temporal Chrono-Effects** - Ghosting trails, time-warp distortion

**New Functions**:
```wgsl
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32
fn sdRoundedBox(p: vec3<f32>, b: vec3<f32>, r: f32) -> f32
fn update_pendulum(p: Pendulum, dt: f32, wind: vec2<f32>) -> Pendulum
fn refract_ray(rd: vec3<f32>, n: vec3<f32>, ior: f32) -> vec3<f32>
fn caustic_pattern(p: vec3<f32>, time: f32) -> f32
```

**RGBA Enhancement**:
- R: Red refracted light (IOR = 1.5)
- G: Green refracted light (IOR = 1.52)
- B: Blue refracted light (IOR = 1.54)
- A: Fresnel reflectance

---

### 7. gen-kinetic-neo-brutalist-megastructure.wgsl (111 lines)

**Current**: Ray-marched brutalist architecture

**5 Expansion Ideas**:
1. **Advanced CSG Operations** - Smooth union, subtraction, intersection
2. **PBR Material System** - Roughness/metallic workflow, GGX distribution
3. **Modular Architectural Kit** - Domain repetition with varied parameters
4. **Volumetric Fog** - Beer-Lambert law, Henyey-Greenstein phase
5. **Procedural Façade Detail** - Windows, vents, panels in object space

**New Functions**:
```wgsl
fn smin(a: f32, b: f32, k: f32) -> f32
fn distributionGGX(N: vec3<f32>, H: vec3<f32>, roughness: f32) -> f32
fn fresnelSchlick(cosTheta: f32, F0: vec3<f32>) -> vec3<f32>
fn getBuildingParams(id: vec3<f32>) -> vec4<f32>
fn volumetricFog(ro: vec3<f32>, rd: vec3<f32>, tMax: f32) -> vec4<f32>
```

**RGBA Enhancement**:
- R: Final color
- G: Final color
- B: Final color
- A: Material ID (0=concrete, 0.5=steel, 1.0=neon)

---

### 8. gen-crystal-caverns.wgsl (113 lines)

**Current**: Crystal cave system with ray marching

**5 Expansion Ideas**:
1. **Crystal Lattice SDFs** - Octahedron, hex prism, pyramid shapes
2. **Subsurface Scattering** - Diffusion approximation, translucency
3. **Caustic Lighting** - Wavefront propagation, intensity concentration
4. **Domain Distortion** - FBM noise for organic cave erosion
5. **Crystal Emission Mask** - Time-based activation, clustering

**New Functions**:
```wgsl
fn sdOctahedron(p: vec3<f32>, s: f32) -> f32
fn sdHexPrism(p: vec3<f32>, h: vec2<f32>) -> f32
fn subsurfaceScattering(p: vec3<f32>, n: vec3<f32>, l: vec3<f32>, thickness: f32, albedo: vec3<f32>) -> vec3<f32>
fn causticIntensity(p: vec3<f32>, sources: array<vec3<f32>, 4>, time: f32) -> f32
fn warpDomain(p: vec3<f32>, time: f32) -> vec3<f32>
```

**RGBA Enhancement**:
- R: Color
- G: Color
- B: Color
- A: Emission strength (bloom input)

---

## Shared Function Library

All upgraded shaders will include:

```wgsl
// ═══ HASH FUNCTIONS ═══
fn hash12(p: vec2<f32>) -> f32
fn hash13(p: vec3<f32>) -> f32
fn hash21(p: vec2<f32>) -> vec2<f32>
fn hash33(p: vec3<f32>) -> vec3<f32>

// ═══ NOISE FUNCTIONS ═══
fn noise(p: vec2<f32>) -> f32
fn noise3D(p: vec3<f32>) -> f32
fn fbm(p: vec2<f32>, octaves: i32) -> f32
fn fbm3D(p: vec3<f32>, octaves: i32) -> f32

// ═══ COLOR UTILITIES ═══
fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32>
fn rgb2hsv(rgb: vec3<f32>) -> vec3<f32>
fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32>
```

---

## Implementation Priority

| Priority | Shader | Reason |
|----------|--------|--------|
| P0 | gen-raptor-mini | Easiest, good foundation practice |
| P0 | gen-xeno-botanical | RD systems highly requested |
| P1 | gen-crystal-caverns | Visual impact high, SSS appealing |
| P1 | gen-lenia-2 | CA enthusiasts will appreciate |
| P2 | gen-astro-orrery | Complex but impressive result |
| P2 | gen-cosmic-web | Already good, incremental upgrade |
| P3 | gen-vitreous-chandelier | Physics-heavy, complex |
| P3 | gen-kinetic-brutalist | PBR system requires testing |

---

## Expected Visual Improvements

| Shader | Before | After |
|--------|--------|-------|
| raptor-mini | Static cellular dots | Territorial swarm with trails |
| xeno-botanical | Simple branches | Growing L-system plants |
| astro-orrery | Rotating rings | Physically accurate orbits |
| cosmic-web | Static Voronoi | Evolving multi-fractal structure |
| lenia-2 | Basic 4-species | DNA-encoded evolving organisms |
| chandelier | Simple octahedrons | Pendulum-swinging crystal arrays |
| brutalist | Repetitive boxes | PBR material variety + fog |
| crystal-caverns | Spheres | Faceted gems with caustics |
