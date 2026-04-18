# Phase C: Advanced Compute Shader Artistry — Swarm Launch

**Phase Timeline:** Weeks 9-14  
**Total New Shaders:** ~60 (15 convolution + 15 mouse-interactive + 15 spectral/computation + 15 alpha artistry)  
**Goal:** Push WebGPU compute to its visual and computational limits with novel techniques not yet in the library

---

## Vision

Phase C is about **techniques that don't exist yet** in the Pixelocity library. Where Phases A and B upgraded existing shaders and created hybrids from known patterns, Phase C introduces:

- **Convolution methods never before implemented** (bilateral, morphological, Gabor, non-local means, guided filtering)
- **Mouse-responsive shaders with physically-inspired interaction models** (fluid coupling, electromagnetic fields, gravity lensing, quantum tunneling)
- **Novel WGSL computation patterns** (subgroup operations, cooperative matrix math, stochastic sampling, spectral rendering)
- **RGBA32FLOAT as a creative medium** — not just "add alpha" but use the full 128-bit-per-pixel pipeline as 4 independent high-dynamic-range data channels for effects impossible in 8-bit pipelines

---

## Quick Start

```bash
cd projects/image_video_effects/swarm-tasks/phase-c

cat agent-1c-rgba-convolution-architect.md      # Novel image convolutions
cat agent-2c-psychedelic-mouse-sculptor.md       # Complex mouse-interactive effects
cat agent-3c-spectral-computation-pioneer.md     # Novel WGSL computation methods
cat agent-4c-alpha-artistry-specialist.md        # RGBA→RGB creative effects
```

---

## Agent Task Summary

| Agent | Role | Target | Duration | Dependencies |
|-------|------|--------|----------|--------------|
| **1C** | RGBA Convolution Architect | 15 convolution shaders | 5-7 days | Phase B complete |
| **2C** | Psychedelic Mouse Sculptor | 15 mouse-interactive shaders | 5-7 days | Phase B complete |
| **3C** | Spectral Computation Pioneer | 15 computation shaders | 5-7 days | Phase B complete |
| **4C** | Alpha Artistry Specialist | 15 RGBA→RGB shaders | 5-7 days | Phase B complete |

---

## Execution Order

### Wave 1: All Agents Launch (Days 1-7)
All four agents are independent and can run in parallel:
- **Agent 1C:** Start with bilateral filter + morphological operators
- **Agent 2C:** Start with electromagnetic mouse field shader
- **Agent 3C:** Start with 4-band spectral renderer
- **Agent 4C:** Start with HDR bloom with alpha-as-exposure

### Wave 2: Cross-Pollination (Days 7-14)
Agents review each other's outputs for combo opportunities:
- 1C convolution kernels feed into 2C mouse-interactive versions
- 3C computation patterns can be layered on 4C alpha effects
- All agents create 2-3 "crossover" shaders using techniques from sister agents

---

## What Makes Phase C Different

### Phase A/B vs Phase C

| Aspect | Phase A/B | Phase C |
|--------|-----------|---------|
| **Alpha** | Luminance-based, depth-layered | Alpha as data channel, 4-field simulation, HDR accumulation |
| **Convolutions** | Sobel, Gaussian, Laplacian, Kuwahara | Bilateral, Gabor, Morphological, Non-Local Means, Guided Filter, Structure Tensor Flow |
| **Mouse** | Ripple physics, displacement | EM fields, quantum tunneling, gravity lensing, fluid coupling, fractal zoom |
| **Computation** | Shared memory tiles, basic atomics | Cooperative reduction, stochastic integration, spectral wavelength rendering, quaternion rotation |
| **RGBA usage** | RGB color + simple alpha | RGBA = 4 independent f32 simulation fields |

---

## Output Locations

| Agent | Output | Location |
|-------|--------|----------|
| 1C | Convolution WGSL | `public/shaders/conv-*.wgsl` |
| 1C | JSONs | `shader_definitions/image/conv-*.json` |
| 2C | Mouse WGSL | `public/shaders/mouse-*.wgsl` |
| 2C | JSONs | `shader_definitions/interactive-mouse/mouse-*.json` |
| 3C | Computation WGSL | `public/shaders/spec-*.wgsl` or `public/shaders/gen-*.wgsl` |
| 3C | JSONs | `shader_definitions/generative/*.json` or `shader_definitions/advanced-hybrid/*.json` |
| 4C | Alpha artistry WGSL | `public/shaders/alpha-*.wgsl` |
| 4C | JSONs | `shader_definitions/artistic/alpha-*.json` or `shader_definitions/visual-effects/alpha-*.json` |

---

## Success Metrics

- [ ] 15 novel convolution shaders (none duplicate existing Sobel/Gaussian/Laplacian)
- [ ] 15 mouse-interactive shaders with physically-inspired interaction models
- [ ] 15 shaders using novel WGSL computation techniques
- [ ] 15 shaders creatively exploiting RGBA32FLOAT beyond simple alpha
- [ ] All 60 shaders compile without errors
- [ ] All shaders use standard immutable bindings
- [ ] Each shader has a JSON definition with params, tags, and description
- [ ] Performance: 30+ FPS at 2048×2048 on mid-range GPU
- [ ] Visual quality: "wow factor" — psychedelic, beautiful, artistically compelling

---

## Key Technical Resources

| Resource | Location |
|----------|----------|
| Ultra Shader Techniques | `docs/ULTRA_SHADER_TECHNIQUES.md` |
| Shared Memory Guide | `docs/SHARED_MEMORY_OPTIMIZATION.md` |
| Texture Optimizations | `docs/TEXTURE_OPTIMIZATIONS.md` |
| Branchless Patterns | `docs/BRANCHLESS_PATTERNS.md` |
| Advanced Alpha (Phase B) | `swarm-tasks/phase-b/agent-2b-advanced-alpha.md` |
| Technical Reference | `swarm-technical-reference.md` |
| Standard Bindings | `AGENTS.md` (Shader Bindings section) |

---

**Status:** 📋 Ready for Launch  
**Prerequisites:** Phase B completion  
**Next Step:** Launch all 4 agents in parallel
