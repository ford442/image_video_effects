# Final Shader Catalog

**Date:** 2026-03-22  
**Total Shaders:** 678  
**Categories:** 15

---

## Category Overview

| Category | Count | % of Total | Description |
|----------|-------|------------|-------------|
| image | 405 | 59.7% | Image processing effects |
| generative | 97 | 14.3% | Procedural/generative art |
| interactive-mouse | 38 | 5.6% | Mouse-driven interactions |
| distortion | 32 | 4.7% | Spatial distortions |
| simulation | 30 | 4.4% | Physics simulations |
| artistic | 20 | 3.0% | Artistic effects |
| visual-effects | 18 | 2.7% | Visual enhancements |
| hybrid | 10 | 1.5% | Hybrid shaders (Phase A) |
| advanced-hybrid | 10 | 1.5% | Advanced hybrids (Phase B) |
| retro-glitch | 13 | 1.9% | Retro/glitch effects |
| lighting-effects | 14 | 2.1% | Lighting effects |
| geometric | 9 | 1.3% | Geometric patterns |
| liquid-effects | 6 | 0.9% | Liquid shaders |
| post-processing | 6 | 0.9% | Post-processing |

---

## Featured Shaders by Category

### 🎨 Advanced Hybrid (Phase B)

| Shader | Complexity | Target FPS | Description |
|--------|------------|------------|-------------|
| hyper-tensor-fluid | Very High | 45+ | Tensor field fluid dynamics |
| neural-raymarcher | Very High | 30+ | Raymarched neural network |
| gravitational-lensing | Very High | 30+ | Schwarzschild black hole |
| cellular-automata-3d | Very High | 30+ | 3D cellular automata |
| chromatic-reaction-diffusion | High | 60 | Per-channel Gray-Scott |
| fractal-boids-field | High | 45-60 | Flocking + fractals |
| holographic-interferometry | High | 60 | Wave interference patterns |
| audio-voronoi-displacement | High | 60 | Audio-driven Voronoi |
| spectral-flow-sorting | High | 45-60 | Pixel sorting + spectra |
| multi-fractal-compositor | High | 45-60 | Multi-layer fractals |

### 🔄 Multi-Pass Shaders

| Shader | Passes | Description |
|--------|--------|-------------|
| quantum-foam | 3 | Quantum field simulation |
| aurora-rift | 2 | Volumetric aurora |
| aurora-rift-2 | 2 | Enhanced aurora |
| sim-fluid-feedback-field | 3 | Navier-Stokes fluid |

### 🎵 Audio-Reactive

| Shader | Pattern | Description |
|--------|---------|-------------|
| gen-audio-spirograph | Bass-pulse | FFT-driven spirograph |
| hybrid-spectral-sorting | FFT-driven | Sorting by frequency |
| liquid_magnetic_ferro | Intensity | Ferrofluid with audio |
| audio-voronoi-displacement | Beat-sync | Audio Voronoi warp |
| retro_phosphor_dream | Bass-pulse | CRT with audio glow |

### 🔬 Simulation

| Shader | Type | Description |
|--------|------|-------------|
| sim-slime-mold-growth | Agent | Physarum simulation |
| sim-fluid-feedback-field | Fluid | Navier-Stokes |
| sim-ink-diffusion | Reaction | Gray-Scott validated |
| sim-sand-dunes | Cellular | Sand dune formation |
| sim-smoke-trails | Particle | Smoke particles |
| sim-heat-haze-field | Thermal | Heat distortion |
| quantum-foam | Quantum | Probability fields |
| pixel-sand | Granular | Falling sand |

### ✨ Hybrid (Phase A)

| Shader | Techniques | Description |
|--------|------------|-------------|
| hybrid-noise-kaleidoscope | FBM + kaleidoscope | Organic symmetry |
| hybrid-sdf-plasma | SDF + plasma | 3D displaced spheres |
| hybrid-chromatic-liquid | Flow + chromatic | RGB liquid motion |
| hybrid-cyber-organic | Hex + growth | Cyber-organic fusion |
| hybrid-voronoi-glass | Voronoi + glass | Physical refraction |
| hybrid-fractal-feedback | Julia + feedback | Temporal RGB delay |
| hybrid-magnetic-field | Curl + field | Magnetic field lines |
| hybrid-particle-fluid | Particle + curl | Divergence-free flow |
| hybrid-reaction-diffusion-glass | RD + glass | Turing patterns |
| hybrid-spectral-sorting | Sort + spectral | Audio pixel sort |

---

## Feature Matrix

| Shader | Mouse | Audio | Depth | Temporal | Multi-Pass |
|--------|-------|-------|-------|----------|------------|
| quantum-foam | ✅ | ❌ | ❌ | ✅ | ✅ (3) |
| neural-raymarcher | ✅ | ❌ | ❌ | ❌ | ❌ |
| hyper-tensor-fluid | ✅ | ❌ | ✅ | ❌ | ❌ |
| gravitational-lensing | ✅ | ❌ | ❌ | ❌ | ❌ |
| sim-fluid-feedback-field | ✅ | ❌ | ❌ | ✅ | ✅ (3) |
| hybrid-spectral-sorting | ✅ | ✅ | ❌ | ❌ | ❌ |
| gen-audio-spirograph | ❌ | ✅ | ❌ | ❌ | ❌ |
| aurora-rift | ❌ | ❌ | ❌ | ✅ | ✅ (2) |

---

## Performance Tiers

### 🟢 60 FPS (Lightweight)
- sim-sand-dunes
- sim-ink-diffusion
- sim-heat-haze-field
- hybrid-noise-kaleidoscope
- Most image effects

### 🟡 45-60 FPS (Moderate)
- hyper-tensor-fluid
- fractal-boids-field
- chromatic-reaction-diffusion
- aurora-rift
- quantum-foam

### 🟠 30-45 FPS (Intensive)
- neural-raymarcher
- gravitational-lensing
- cellular-automata-3d
- sim-slime-mold-growth

---

## New in This Release

### Phase A (84 shaders)
- 61 upgraded with RGBA support
- 10 hybrid shaders
- 13 generative shaders

### Phase B (~185 shaders)
- 7 multi-pass pass files
- 50 optimized shaders
- 50 alpha-enhanced shaders
- 18 advanced hybrids
- 50+ audio-reactive shaders
- 10 simulation shaders

---

## Shader Count by Creation

| Source | Count |
|--------|-------|
| Original Library | ~400 |
| Agent 1A (Alpha Upgrade) | 61 |
| Agent 2A (Hybrids) | 10 |
| Agent 4A (Generative) | 13 |
| Agent 1B (Multi-Pass + Opt) | ~50 |
| Agent 2B (Alpha) | ~50 |
| Agent 3B (Advanced Hybrids) | 18 |
| Agent 4B (Audio) | ~50 |
| **Total** | **~680** |

---

## Quick Search Index

### By Technique
- **Raymarching:** neural-raymarcher, gravitational-lensing
- **FBM:** Most generative and hybrid shaders
- **Voronoi:** hybrid-voronoi-glass, audio-voronoi-displacement
- **Reaction-Diffusion:** chromatic-reaction-diffusion, sim-ink-diffusion
- **Navier-Stokes:** sim-fluid-feedback-field, navier-stokes-dye
- **Cellular Automata:** cellular-automata-3d, pixel-sand, sim-sand-dunes
- **Agent-Based:** sim-slime-mold-growth, boids, fractal-boids-field

### By Visual Style
- **Cyber:** hybrid-cyber-organic, cyber-* shaders
- **Organic:** sim-slime-mold-growth, hybrid-noise-kaleidoscope
- **Space/Cosmic:** aurora-rift, quantum-foam, gravitational-lensing
- **Retro:** retro_phosphor_dream, retro-glitch/*
- **Liquid:** liquid-*, sim-fluid-*

---

*Catalog generated by Agent 5B*  
*Date: 2026-03-22*
