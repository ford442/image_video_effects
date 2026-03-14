# Liquid Category Shader Upgrade Plan

## Category Summary

The Liquid shader category currently contains **26 shaders** ranging from simple displacement effects to complex fluid simulations. The category represents the intersection of artistic visual effects and computational fluid dynamics approximations.

### Current Category Statistics
| Metric | Value |
|--------|-------|
| Total Shaders | 26 |
| Total Code Size | ~120KB |
| Average Shader Size | 4,608 bytes |
| Smallest Shader | liquid-displacement (2,889 bytes) |
| Largest Shader | liquid-v1 (9,183 bytes) |
| Multi-pass Shaders | 6 |
| Mouse-Driven Shaders | 22 |
| Depth-Aware Shaders | 14 |

### Current Technique Distribution
- **Basic UV Displacement**: 10 shaders
- **Ripple/Wave Simulation**: 8 shaders
- **Vortex/Swirl Effects**: 4 shaders
- **Feedback/Temporal Effects**: 3 shaders
- **Volumetric/Multi-layer**: 2 shaders
- **Surface Normal Mapping**: 3 shaders

---

## Shader Analysis Table with Priority Ranking

| Rank | Shader | Size | Current Technique | Upgrade Priority | Complexity |
|------|--------|------|-------------------|------------------|------------|
| 1 | liquid-viscous | 7,057 | Vortex physics with neighbor smoothing | ⭐⭐⭐⭐⭐ CRITICAL | Hard |
| 2 | liquid-touch | 5,542 | Height field simulation with diffusion | ⭐⭐⭐⭐⭐ CRITICAL | Hard |
| 3 | liquid-warp | 3,137 | Velocity field with feedback | ⭐⭐⭐⭐⭐ CRITICAL | Medium |
| 4 | liquid-volumetric-zoom | 7,094 | Multi-layer depth compositing | ⭐⭐⭐⭐ HIGH | Hard |
| 5 | liquid-oil | 3,365 | Flow noise with interference | ⭐⭐⭐⭐ HIGH | Medium |
| 6 | liquid-time-warp | 4,680 | Temporal advection feedback | ⭐⭐⭐⭐ HIGH | Medium |
| 7 | liquid-smear | 4,157 | History-based smearing | ⭐⭐⭐ MEDIUM | Medium |
| 8 | liquid-v1 | 9,183 | Complex multi-effect lighting | ⭐⭐⭐ MEDIUM | Hard |
| 9 | liquid-zoom | 7,466 | Parallax zoom with depth | ⭐⭐⭐ MEDIUM | Medium |
| 10 | liquid-perspective | 7,937 | Foreground masking with warp | ⭐⭐⭐ MEDIUM | Medium |
| 11 | liquid-viscous-simple | 4,625 | Simplified vortex with chromatic | ⭐⭐⭐ MEDIUM | Easy |
| 12 | liquid-metal | 4,816 | Normal-based chrome mapping | ⭐⭐⭐ MEDIUM | Medium |
| 13 | liquid-chrome-ripple | 3,864 | Normal perturbation with ripple | ⭐⭐ MEDIUM | Easy |
| 14 | liquid-lens | 4,154 | Spherical lens refraction | ⭐⭐ MEDIUM | Easy |
| 15 | liquid-prism | 3,587 | Radial wave with RGB split | ⭐⭐ MEDIUM | Easy |
| 16 | liquid-warp-interactive | 4,063 | Flow noise with mouse influence | ⭐⭐ MEDIUM | Easy |
| 17 | liquid-jelly | 2,958 | Elastic bounce with depth mask | ⭐⭐ LOW | Easy |
| 18 | liquid-displacement | 2,889 | Bulge/pinch with chromatic | ⭐⭐ LOW | Easy |
| 19 | liquid-mirror | 3,249 | Metallic reflection with waves | ⭐⭐ LOW | Easy |
| 20 | liquid-swirl | 3,087 | Rotational twist with angle falloff | ⭐ LOW | Easy |
| 21 | liquid-glitch | 3,145 | Block-based digital distortion | ⭐ LOW | Easy |
| 22 | liquid-rainbow | 3,069 | Time-varying RGB offset | ⭐ LOW | Easy |
| 23 | liquid-fast | 3,243 | Accelerated ripple variant | ⭐ LOW | Easy |
| 24 | liquid | 3,066 | Base ripple with ambient motion | ⭐ LOW | Easy |
| 25 | liquid-rgb | 3,722 | RGB channel separation | ⭐ LOW | Easy |
| 26 | liquid-viscous-grokcf1 | 6,675 | Variant viscosity test | ⭐ LOW | Easy |

---

## Top 5 Upgrade Candidates - Detailed Plans

---

### #1: LIQUID-VISCOUS → "Turbulent Viscous Flow"

**Current Description:**
A sophisticated vortex-based displacement shader that creates fluid-like motion through tangential velocity calculations around click points. Features multi-octave ambient flow, depth-aware masking, neighbor-based smoothing (4-tap cardinal sampling), and chromatic aberration based on displacement magnitude.

**Current Limitations:**
- Vortex physics lacks proper vorticity confinement
- No turbulence cascade (energy dies without transition to smaller eddies)
- Neighbor smoothing is isotropic (doesn't follow flow direction)
- No viscosity gradients (fluid has uniform thickness)

**Artistic Upgrade Concept:**
Transform into a **turbulent shear flow** that mimics honey being stirred, where large vortices break down into smaller swirling patterns, creating organic, painterly motion that feels like thick liquid in motion.

**Visual Reference:**
"Slow-motion footage of colored dyes in glycerin—large coherent structures that gracefully fragment into delicate tendrils, with bright highlights where light catches the shear boundaries"

**Computational Technique to Add:**

1. **Vorticity Confinement (Fedkiw et al. method)**
   ```
   ω = ∇ × v (curl of velocity field)
   N = ∇|ω| / |∇|ω|| (normalized vorticity gradient)
   f_vc = ε × dx × (N × ω) (confinement force)
   ```
   This re-injects energy into swirling regions, preventing dissipation.

2. **Anisotropic Diffusion along Streamlines**
   Instead of isotropic neighbor averaging, diffuse along the velocity direction:
   ```
   D_parallel = high (along flow)
   D_perpendicular = low (across flow)
   ```
   This preserves sharp shear boundaries while smoothing along flow direction.

3. **Reynolds-Number-Based Turbulence Transition**
   ```
   Re = (velocity_scale × length_scale) / viscosity
   If Re > Re_critical: inject sub-grid turbulence noise
   ```
   Creates automatic transition from laminar to turbulent flow.

**Implementation Complexity:** HARD
- Requires velocity field storage (already has dataTextureA/B/C)
- Needs curl calculation (6 additional texture samples)
- Requires 2-pass approach for stable diffusion

**Dependencies:**
- Uses existing dataTextureA/B/C for ping-pong velocity
- Requires writeDepthTexture for depth masking
- Needs extraBuffer for parameter tuning

---

### #2: LIQUID-TOUCH → "Surface Tension Ripple Simulation"

**Current Description:**
A height-field-based liquid simulation where mouse interaction creates height perturbations that propagate and diffuse. Uses 4-tap neighbor sampling for diffusion and gradient-based refraction for visualization.

**Current Limitations:**
- Diffusion is simple box blur (not wave equation)
- No surface tension effects (ripples don't have that characteristic "water droplet" look)
- No dispersion (all frequencies travel at same speed)
- No capillary wave effects at small scales

**Artistic Upgrade Concept:**
Evolve into a **capillary wave simulator** that captures the mesmerizing patterns of water droplets on a still pool—circular ripples that interact, reflect from boundaries, and exhibit the characteristic wavelength-dependent dispersion that makes real water so captivating.

**Visual Reference:**
"High-speed photography of a droplet hitting water—the crown formation, the rebound spike, and the expanding ring of capillary waves with their distinctive short wavelength near the center and longer wavelengths at the edges"

**Computational Technique to Add:**

1. **Wave Equation with Dispersion (improved from current)**
   ```
   ∂²h/∂t² = c²∇²h - γ∇⁴h (linearized capillary-gravity waves)
   where c = wave speed, γ = surface tension coefficient
   ```
   The ∇⁴ term adds the characteristic frequency-dependent dispersion.

2. **Kelvin-Helmholtz Instability Approximation**
   When shear is detected between adjacent wave fronts:
   ```
   if |∇h × velocity| > threshold:
       inject small-scale noise at interface
   ```
   Creates those beautiful breaking-wave patterns at crests.

3. **Laplace Pressure-Based Surface Tension**
   ```
   P_surface = σ × (1/R₁ + 1/R₂) = σ × ∇²h
   acceleration += P_surface × direction
   ```
   Makes small droplets hold together, large ones flatten.

**Implementation Complexity:** HARD
- Needs velocity + height dual field (currently only height)
- Requires boundary condition handling
- Needs larger stencil (8 or 12 samples for ∇⁴)

**Dependencies:**
- dataTextureA for height field (current)
- dataTextureB for velocity field (NEW)
- dataTextureC for previous state
- Requires multi-pass for stability

---

### #3: LIQUID-WARP → "Navier-Stokes Advection"

**Current Description:**
A velocity field system where mouse interactions add velocity vectors that decay over time. The velocity field advects texture coordinates, creating a "smearing" effect. Uses simple noise-based flow as baseline.

**Current Limitations:**
- Velocity just decays (no conservation of momentum)
- No pressure projection (velocity field not divergence-free)
- No advection of the velocity field itself
- Self-advection is the key missing ingredient for true fluid behavior

**Artistic Upgrade Concept:**
Elevate to a **full Navier-Stokes inspired flow** where the liquid carries its own motion—the velocity field moves itself, creating those beautiful self-sustaining swirls that seem alive, like ink dispersing in water or cream swirling in coffee.

**Visual Reference:**
"Schlieren photography of convection currents—ghostly, ever-evolving patterns of rising and falling fluid, with sheets of motion folding into each other like phantom fabric"

**Computational Technique to Add:**

1. **Semi-Lagrangian Advection (Stam's method)**
   ```
   velocity_new(x) = velocity_old(x - velocity_old(x) × dt)
   ```
   The velocity field carries itself along its own flow lines.

2. **Jacobi Pressure Projection (simplified)**
   ```
   ∇ · velocity = divergence
   Solve: ∇²p = divergence  (2-4 Jacobi iterations)
   velocity = velocity - ∇p
   ```
   Makes the flow incompressible—no sources or sinks.

3. **Coanda Effect Approximation**
   ```
   When flow is near a boundary:
       add force perpendicular to boundary, pointing into flow
   ```
   Makes fluid "stick" to and curve around obstacles.

**Implementation Complexity:** MEDIUM
- Can reuse existing velocity storage in dataTextureA
- Requires ping-pong between A and C
- Pressure solve needs 2-4 passes (can be same frame)

**Dependencies:**
- dataTextureA/C for velocity ping-pong
- readTexture for final color advection
- May need extraBuffer for divergence storage

---

### #4: LIQUID-VOLUMETRIC-ZOOM → "Rayleigh-Taylor Mixing Layers"

**Current Description:**
A sophisticated multi-layer system that samples the texture at 5 depth layers, each with independent zoom and flow distortion. Creates a volumetric "tunnel" effect with fog and chromatic separation.

**Current Limitations:**
- Layers don't interact (no mixing between depth slices)
- Flow is just noise-based (no buoyancy or density effects)
- No instability when dense fluid is above light fluid
- Fixed layer count (5 layers, hardcoded)

**Artistic Upgrade Concept:**
Transform into a **density-stratified turbulent mixing** effect—like oil and water shaken together, or hot smoke rising through cold air, with beautiful Rayleigh-Taylor fingers and Kelvin-Helmholtz waves at the interfaces between layers.

**Visual Reference:**
"Astronomical images of the Crab Nebula—tendrils of glowing gas interpenetrating in complex, fractal-like patterns, with bright knots where shocks form and darker, denser filaments threading through"

**Computational Technique to Add:**

1. **Rayleigh-Taylor Instability Procedural Generation**
   ```
   For each interface between layers:
       perturbed_interface = base + A(t) × sin(k × x + φ) × exp(σt)
       where σ = √(At × g × k), At = (ρ₁-ρ₂)/(ρ₁+ρ₂)
   ```
   Creates the characteristic "finger" formations.

2. **Vorticity-Layer Coupling**
   ```
   vorticity at layer i affects velocity at layer i±1
   with falloff based on distance
   ```
   Couples the layers so they influence each other.

3. **Buoyancy-Driven Flow**
   ```
   acceleration = density_gradient × gravity_direction
   velocity += acceleration × dt
   ```
   Lighter layers rise, heavier layers sink.

**Implementation Complexity:** HARD
- Needs layer-to-layer communication
- Requires density field per layer
- May need compute shader dispatch per layer

**Dependencies:**
- Uses all dataTextures
- Requires plasmaBuffer for shared parameters
- May need extraBuffer for layer densities

---

### #5: LIQUID-OIL → "Thin-Film Interference Fluid"

**Current Description:**
Uses flow noise to create slowly evolving displacement patterns, with a simple cosine-based "oil slick" interference pattern overlaid based on displacement magnitude.

**Current Limitations:**
- Interference is just RGB phase offset (not physically based)
- No thickness variation (oil thickness determines color)
- Flow is generic noise (not thin-film specific)
- No iridescence based on viewing angle

**Artistic Upgrade Concept:**
Evolve into a **physical thin-film interference** simulation—capturing the hypnotic, angle-dependent iridescence of oil on water, soap bubbles, or beetle wings, where the color directly encodes film thickness and viewing angle.

**Visual Reference:**
"Macro photography of a soap bubble—swirling patterns of electric blues, magentas, and golds that shift as the film drains, with darker regions where the film is thinnest and brilliant iridescence where it's just the right thickness for constructive interference"

**Computational Technique to Add:**

1. **Physical Thin-Film Interference Model**
   ```
   For light wavelength λ, film thickness d, refractive index n:
   phase_difference = (2π/λ) × 2nd × cos(θ_refracted)
   reflectance = f(phase_difference, polarization)
   
   Sample 3 wavelengths (R=650nm, G=530nm, B=460nm)
   ```
   Produces physically accurate iridescence.

2. **Thickness Advection Equation**
   ```
   ∂d/∂t = -v·∇d + D∇²d + source - drain
   where v = flow velocity, D = diffusion, drain = evaporation
   ```
   Film thickness evolves like a conserved scalar.

3. **Marangoni Flow (surface tension gradient)**
   ```
   flow_acceleration += ∇surface_tension × film_thickness_gradient
   ```
   Regions of different thickness flow toward each other.

**Implementation Complexity:** MEDIUM
- Requires film thickness storage (dataTextureA)
- Needs angle-dependent calculations (view vector)
- Thickness evolution needs advection

**Dependencies:**
- dataTextureA for film thickness
- dataTextureC for velocity/flow
- Need uniform for refractive index

---

## Artistic Vision Board

### Visual Style Descriptions

#### "Honey in Sunlight"
*For: liquid-viscous upgrade*
Thick, golden fluid with extreme viscosity. Large coherent structures dominate the flow, with edges that remain sharp despite motion. Light catches on shear boundaries creating bright, reflective highlights. When disturbed, the motion is slow and deliberate—like watching time-lapse of geological flow. Colors: amber, gold, warm highlights against deep shadows.

#### "Capillary Crown"
*For: liquid-touch upgrade*
The moment of impact frozen in mathematics. Concentric rings of waves emanate from interaction points, with wavelength increasing outward—short, tight ripples near the center becoming longer, gentler undulations at distance. When rings meet, they create complex interference patterns of peaks and troughs. Surface tension holds the pattern in delicate balance. Colors: cool blues, cyan highlights, white sparkle on crests.

#### "Coffee and Cream"
*For: liquid-warp upgrade*
Turbulent mixing at the boundary of two fluids. Cream poured into coffee creates filamentary structures—sheets and tendrils that fold and stretch. The boundary between light and dark is fractal, with structure at all scales. Motion is self-sustaining, with small eddies spinning off larger structures. Colors: rich browns, creamy whites, caramel gradients.

#### "Nebula Fingers"
*For: liquid-volumetric-zoom upgrade*
Cosmic-scale fluid instability. Dense fingers of material plunge into lighter substrate, creating mushroom-shaped formations. At the boundaries, Kelvin-Helmholtz waves ripple like flags in wind. The 3D depth is palpable—layers at different depths move independently yet influence each other. Colors: deep space blacks, neon magentas, electric blues, dusted with star-bright highlights.

#### "Oil Slick Rainbow"
*For: liquid-oil upgrade*
The surface of a puddle with oil—an ever-changing palette that shifts with viewing angle. Thinner regions show blues and cyans, thicker regions golds and magentas. As the film drains or flows, colors migrate and swirl, encoding the thickness topography. The effect is hypnotic, drawing the eye to follow the color gradients. Colors: full spectrum iridescence, shifting through rainbow sequences.

#### "Molten Chrome"
*For: liquid-metal upgrade (future)*
Liquid metal at high temperature, with a mirror-like surface that reflects distorted versions of the environment. Surface tension creates smooth, blob-like formations with occasional oscillations. Highlights are intense and specular, edges are crisp. Motion has weight and momentum—like mercury but hotter, more alive. Colors: silvers, steel blues, white-hot highlights.

---

## Computational Techniques Glossary

### Fluid Dynamics Concepts

#### Navier-Stokes Equations
The fundamental equations governing fluid motion:
```
∂u/∂t + (u·∇)u = -(1/ρ)∇p + ν∇²u + f
∇·u = 0
```
Where u=velocity, p=pressure, ρ=density, ν=viscosity, f=external forces.

**Application:** Core of realistic fluid simulation. The first equation is momentum conservation; the second enforces incompressibility.

---

#### Reynolds Number (Re)
Dimensionless number predicting flow patterns:
```
Re = (ρ × u × L) / μ = inertial forces / viscous forces
```
- Re < 2300: Laminar flow (smooth, predictable)
- Re > 4000: Turbulent flow (chaotic, mixing)

**Application:** Determine when to inject turbulence noise or switch to different simulation modes.

---

#### Surface Tension / Laplace Pressure
Pressure difference across a curved interface:
```
ΔP = σ × (1/R₁ + 1/R₂) = σ × κ
```
Where σ=surface tension coefficient, R=principal radii of curvature, κ=mean curvature.

**Application:** Makes small droplets spherical, creates capillary waves, drives Marangoni flow.

---

#### Vorticity Confinement
Technique to preserve small-scale rotational structures:
```
ω = ∇ × u (vorticity)
N = ∇|ω| / |∇|ω||
f_vc = ε × h × (N × ω)
```
Where ε is user-tunable confinement strength.

**Application:** Prevents numerical diffusion from destroying interesting swirling motion.

---

#### Capillary Waves
Short-wavelength surface waves dominated by surface tension (not gravity):
```
ω² = (σ/ρ) × k³
where k = 2π/λ (wavenumber)
```
Dispersion relation shows frequency depends on wavelength to the 3/2 power.

**Application:** Creates the characteristic "ripples on a pond" look with correct wave speed variation.

---

#### Coanda Effect
Tendency of a fluid jet to stay attached to a curved surface:
```
F_coanda = pressure_difference × surface_normal
```

**Application:** Makes fluid curve around obstacles, follow container walls, create attachment-based flow patterns.

---

#### Kelvin-Helmholtz Instability
Occurs at the interface between two fluids with velocity shear:
```
Growth rate: ω = i × (ρ₁ρ₂/(ρ₁+ρ₂) × |Δu|² × k - σk³)
```

**Application:** Creates the characteristic "breaking wave" patterns at fluid interfaces—cloud formations, ocean waves, cosmic gas clouds.

---

#### Rayleigh-Taylor Instability
Occurs when dense fluid is accelerated into lighter fluid:
```
Growth rate: γ = √(At × g × k)
Atwood number: At = (ρ₁-ρ₂)/(ρ₁+ρ₂)
```

**Application:** Creates the "finger" formations when oil penetrates water, or supernova remnants expand.

---

#### Smoothed Particle Hydrodynamics (SPH) Approximations
Particle-based fluid simulation adapted for grid:
```
A(x) = Σ mⱼ × (Aⱼ/ρⱼ) × W(x-xⱼ, h)
```
Where W is a smoothing kernel, h is smoothing length.

**Application:** Can approximate particle-like behavior on grid—blobby coalescence, surface tension effects.

---

#### Semi-Lagrangian Advection
Stable method for moving quantities along flow:
```
φ(x, t+Δt) = φ(x - u(x,t)×Δt, t)
```

**Application:** Core technique for stable fluid simulation—allows large timesteps without instability.

---

#### Jacobi Pressure Projection
Iterative method to enforce incompressibility:
```
Repeat 20-40 times:
    p_new(i,j) = (p_old(i+1,j) + p_old(i-1,j) + 
                  p_old(i,j+1) + p_old(i,j-1) - 
                  divergence(i,j)) / 4
```

**Application:** Removes divergence from velocity field, making flow incompressible (volume-preserving).

---

## Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)
- Implement basic pressure projection for liquid-warp
- Add velocity field dual-buffer to liquid-touch
- Create shared utility functions for curl/divergence/gradient

### Phase 2: Core Physics (Weeks 3-4)
- Add vorticity confinement to liquid-viscous
- Implement wave equation with dispersion for liquid-touch
- Add semi-Lagrangian advection to liquid-warp

### Phase 3: Advanced Effects (Weeks 5-6)
- Implement Rayleigh-Taylor instability in liquid-volumetric-zoom
- Add physical thin-film interference to liquid-oil
- Add anisotropic diffusion to liquid-viscous

### Phase 4: Polish & Integration (Weeks 7-8)
- Parameter tuning and artist-friendly controls
- Performance optimization
- Cross-shader technique sharing

---

## Notes for Implementation

### WGSL Considerations
- All shaders use `@workgroup_size(8, 8, 1)`—maintain this for consistency
- Texture coordinates use `uv` naming convention—preserve for readability
- Time is in `u.config.x`—consistent across all shaders
- Depth texture provides foreground/background masking

### Performance Guidelines
- Keep texture samples under 16 per invocation for 60fps
- Use `mix()` instead of branches where possible
- Prefer analytical derivatives over finite differences when accurate
- Ping-pong textures (A→C→A) for iterative methods

### Artistic Control Parameters
Each upgraded shader should expose:
- **Intensity/Strength** (0-1): Overall effect magnitude
- **Scale/Size** (0-1): Spatial frequency of features
- **Speed/Time Scale** (0-1): Temporal evolution rate
- **Turbulence/Complexity** (0-1): Amount of fine detail
- **Viscosity/Damping** (0-1): How quickly motion dissipates

---

*Document generated for Pixelocity Shader Upgrade Initiative*
*Focus: Liquid Category Enhancement through Scientific Accuracy*
