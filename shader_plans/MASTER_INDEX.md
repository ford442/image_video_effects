# Shader Upgrade Plans - Master Index

> **Upgrade law (live):** [`docs/SHADER_UPGRADE_BATCH.md`](../docs/SHADER_UPGRADE_BATCH.md)
> An upgrade **adds 2–4 named, effect-native visual ideas** to the existing picture.
> Bindings / ACES / alpha / sliders / `updatedParams` / naga / springs-for-completeness
> are the **floor**, not the upgrade. Size tiers and science lists below only decide
> *which ideas to add* and *in what order*. They are not a completeness checklist.
> Hygiene-only = not upgraded. Rewrite-as-new-motif = not upgraded (that is a new shader).

> **Reading the per-shader entries:** every "Upgrade Concept", "→ New Name",
> "Transform …", "Replace …" or "Upgrade to simulate …" line below is a **candidate
> idea to add**, not a target the file must be rebuilt into. Read it as *"add X as 1–2
> native ideas; keep the effect's identity, kernel, modes and saved params."* Pick 2–4
> per file for its Idea Card. Do not stamp the same concept across a whole batch.
> Parameter lists name quantities an idea *may* drive — map them onto the file's existing
> param roles; saved `params` stay byte-exact (no renames, no re-defaults).

**Generated:** March 2026  
**Swarm Mission:** Scout candidate native ideas to *add* to 200+ existing shaders (idea scouts, not a completeness standard)

---

## Swarm Intelligence Report

Six specialized agents were deployed to analyze shader categories using scientific concepts from Wolfram. Each agent produced a category idea scout: per-shader lists of candidate additions, not a spec each file must be brought up to.

---

## Category Plans

| Category | File | Lines | Shaders Analyzed | Key Scientific Concepts |
|----------|------|-------|------------------|------------------------|
| **Liquid** | [liquid_upgrades.md](liquid_upgrades.md) | 541 | 26 | Navier-Stokes, Vorticity, Surface Tension, Kelvin-Helmholtz |
| **Chromatic** | [chromatic_upgrades.md](chromatic_upgrades.md) | 806 | 22 | Dispersion, Thin-Film Interference, Birefringence, Grating Diffraction |
| **Generative** | [generative_upgrades.md](generative_upgrades.md) | 384 | 49+ | Reaction-Diffusion, Strange Attractors, Cellular Automata, L-systems |
| **Distortion** | [distortion_upgrades.md](distortion_upgrades.md) | 682 | 27 | General Relativity, Conformal Mapping, Elastic Deformation, Shockwaves |
| **Glitch/Retro** | [glitch_upgrades.md](glitch_upgrades.md) | 425 | 29 | DSP Errors, MPEG Artifacts, VHS Signal Chain, CRT Phosphor Physics |
| **Lighting** | [lighting_upgrades.md](lighting_upgrades.md) | 979 | 35 | Blackbody Radiation, Volumetric Scattering, Fresnel Equations, Caustics |
| **Interactive** | [interactive_upgrades.md](interactive_upgrades.md) | 557 | 33 | Haptic Feedback, Spring-Mass-Damper (pointer-led effects only), Thermal Diffusion, Fluid Impulse |
| **Glitch (research)** | [glitch_shaders_upgrade_plan.md](glitch_shaders_upgrade_plan.md) | 1,048 | 16 | Signal degradation, DCT/MPEG, CRT phosphor, VHS, dithering |

**Total:** 4,374 lines of planning across **221+ shaders**

---

## Quick Reference: Candidate Ideas by Tier

Size tiers set **order of work only**. Each concept below is **one candidate idea to add** to
that file's existing picture — keep its identity, kernel, modes and saved params, and pick
2–4 ideas per file in its Idea Card. Line counts / KB are not a success metric.

### 🔴 Tier 1: Easy Wins (< 2KB shaders)

| Shader | Category | Current | Candidate idea (additive) | Complexity |
|--------|----------|---------|-----------------|------------|
| gen_orb | Generative | Simple orb | Lorenz attractor trail layer around the orb (orb stays) | Easy |
| gen_grokcf_interference | Generative | Interference | Chladni nodal-line layer on the existing interference | Easy |
| gen_grid | Generative | Grid pattern | Domain-warped FBM on the grid UVs (grid stays a grid) | Easy |
| gen_grokcf_voronoi | Generative | Voronoi | Extra Worley octave + cell-edge detail | Easy |
| texture | Core | Render pass | - | N/A |

### 🟠 Tier 2: High Impact (2-4KB shaders)

| Shader | Category | Candidate idea (additive) | Science |
|--------|----------|-----------------|---------|
| liquid-viscous | Liquid | Turbulent viscous flow | Vorticity confinement |
| liquid-touch | Liquid | Surface tension ripples | Laplace pressure |
| chromatic-shockwave | Chromatic | Prismatic shockwave | Cauchy dispersion |
| rgb-ripple-distortion | Chromatic | Photoelastic stress | Birefringence |
| gravity-lens | Distortion | Einstein rings | Schwarzschild metric |
| sonic-distortion | Distortion | Mach cones | Rankine-Hugoniot |
| byte-mosh | Glitch | Bit corruption chains | Error propagation |
| photonic-caustics | Lighting | Wave optics caustics | Photon mapping |
| neon-pulse | Lighting | Blackbody glow | Planck's law |
| quantized-ripples | Interactive | Haptic ripple field | Piezoelectric |

---

## Scientific Concepts Glossary

### Fluid Dynamics
- **Navier-Stokes equations** - Core fluid motion equations
- **Vorticity confinement** - Preserving turbulent swirls
- **Kelvin-Helmholtz instability** - Shear layer billowing
- **Rayleigh-Taylor instability** - Density interface mixing
- **Surface tension (Laplace pressure)** - Capillary effects

### Optics/Light
- **Chromatic aberration (Cauchy)** - Wavelength-dependent refraction
- **Thin-film interference** - Oil slick iridescence
- **Fresnel equations** - View-dependent reflectivity
- **Blackbody radiation** - Temperature-based glow
- **Mie scattering** - Volumetric light in participating media

### Mathematics/Fractals
- **Strange attractors** - Lorenz, Rössler, chaotic systems
- **Reaction-diffusion** - Turing patterns, Gray-Scott
- **Conformal mappings** - Complex plane transformations
- **Cellular automata** - Conway's Life, Lenia, SmoothLife
- **L-systems** - Fractal plant growth

### Signal Processing
- **DCT blocking** - JPEG compression artifacts
- **Motion vectors** - P-frame prediction
- **Chroma subsampling** - YUV 4:2:0 errors
- **Dithering** - Bayer, Floyd-Steinberg, blue noise
- **Quantization** - Bit-depth reduction errors

### Relativity/Physics
- **Gravitational lensing** - Einstein rings
- **Schwarzschild metric** - Black hole spacetime
- **Shock waves** - Mach cones, supersonic flow
- **Spring-mass-damper** - Elastic deformation (only for effects that are already pointer-led; never added for contract completeness)
- **Thermal diffusion** - Heat equation

---

## Implementation Roadmap (order of work, not a standard)

Every phase below means: **write an Idea Card per file, add 2–4 native ideas, apply the
floor.** No phase is "bring these files up to one standard." Timeframe is months at library
scale — see [`docs/SHADER_UPGRADE_BATCH.md`](../docs/SHADER_UPGRADE_BATCH.md) §5–§6.

### Phase 1: Foundation
- Start with Tier 1 (<2KB) files — smallest first is an ordering rule, not a quality metric
- Each file gets its own Idea Card; ideas come from its category scout
- Optional small helpers (WGSL has no `#include`, so copy-paste per file). Helpers and
  templates are never the goal and do not count as an upgrade

### Phase 2: Core Physics (as native ideas)
- Liquid: add one extra field or force the existing solver already implies
- Chromatic: add dispersion detail on top of the existing RGB split
- Distortion: add lensing/ring detail to lenses that are already lenses

### Phase 3: Advanced Effects (as native ideas)
- Lighting: volumetric / phase-function detail where the file already has shafts or glow
- Glitch: one more real signal-chain artifact that fits the existing glitch
- Generative: one new geometric or temporal layer fused to the existing motif

### Phase 4: More ideas on files that already have the floor
- Files with bindings / ACES / alpha / `updatedParams` but no native ideas are **not upgraded**
  — give them Idea Cards; do not treat the floor as done
- Performance and parameter tuning without renaming or re-defaulting saved `params`
- No "visual coherence pass" that homogenizes files toward one look

---

## Artistic Vision Themes

Themes to draw candidate ideas from, applied per file only where native. Not a standard every
file must reach.

1. **Physical Realism** - Ground effects in actual physics equations
2. **Scientific Visualization** - Make invisible phenomena visible
3. **Temporal Evolution** - Systems that feel alive and responsive
4. **Multi-Scale Detail** - From macro structures to micro-textures
5. **Interactive Physics** - Mouse as force, energy, or disturbance (only on effects the pointer already drives)

---

## Cross-Category Opportunities

Some scientific concepts can enhance multiple shader families. A ✓ marks a **candidate**, not a
requirement — do not stamp one concept across a whole batch (live contract §4, "generic overlay"):

| Concept | Liquid | Chromatic | Distortion | Lighting | Interactive |
|---------|--------|-----------|------------|----------|-------------|
| **Vorticity** | ✓ Core | - | ✓ Warp | - | ✓ Drag |
| **Dispersion** | ✓ Oil | ✓ Core | ✓ Prism | ✓ Flare | - |
| **Caustics** | ✓ Water | ✓ Lens | ✓ Glass | ✓ Core | - |
| **Noise FBM** | ✓ Turbulence | ✓ Aberration | ✓ Glass | ✓ Cloud | ✓ Force |
| **Feedback** | ✓ Trails | ✓ Ghosting | ✓ Zoom | ✓ Echo | ✓ Echo |

---

## Notes for Developers

- Each category plan includes detailed shader-by-shader analysis — every entry is a candidate *addition* to the existing effect
- A file that only received the floor is "hygiene, not upgraded" — do not stamp `Upgraded:`
- Scientific formulas are included but not code
- Implementation complexity is rated (Easy/Medium/Hard)
- Dependencies and data texture usage are documented
- Artistic references provide visual targets

---

*Generated by Agent Swarm Intelligence*  
*Scientific consultation: Wolfram Alpha/Mathematica*
