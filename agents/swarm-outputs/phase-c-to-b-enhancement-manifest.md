# Phase C → Phase B Enhancement Manifest

**Goal:** Apply completed Phase C advanced concepts to Phase B upgraded shaders.
**Approach:** Create NEW hybrid shaders that combine Phase B base effects with Phase C techniques.
**Date:** 2026-04-18

---

## Phase C Concepts Available (Completed or In-Progress)

### Spectral / Physical Light
- `spec-prismatic-dispersion` — Cauchy's equation, wavelength-based refraction
- `spec-iridescence-engine` — Thin-film interference, soap bubble/oil slick colors
- `spec-blackbody-thermal` — Planck's law, temperature-to-color mapping

### RGBA-as-Data Simulation
- `alpha-fluid-simulation-paint` — Full Navier-Stokes in RGBA
- `alpha-reaction-diffusion-rgba` — 4-species Gray-Scott in RGBA

### Convolution
- `conv-bilateral-dream` — Edge-preserving bilateral filter
- `conv-morphological-erosion-dilation` — Mathematical morphology
- `conv-gabor-texture-analyzer` — Oriented texture detection
- `conv-non-local-means` — Patch-similarity denoising

### Mouse Physics
- `mouse-electromagnetic-aurora` — EM field distortion
- `mouse-fluid-coupling` — Viscous fluid stirring

---

## Enhancement Assignments

### CB-1: Spectral & Physical Light Enhancer
Target Phase B shaders + Phase C technique → New shader name

| Target | Technique | New Shader Name |
|--------|-----------|-----------------|
| `stellar-plasma` | blackbody thermal | `stellar-plasma-blackbody` |
| `aurora-rift` | iridescence | `aurora-rift-iridescence` |
| `liquid-metal` | prismatic dispersion | `liquid-metal-prismatic` |
| `sim-smoke-trails` | blackbody thermal | `sim-smoke-trails-thermal` |
| `sim-heat-haze-field` | blackbody thermal | `sim-heat-haze-blackbody` |

### CB-2: RGBA Simulation Upgrader
| Target | Technique | New Shader Name |
|--------|-----------|-----------------|
| `chromatic-reaction-diffusion` | 4-species RGBA | `chromatic-reaction-diffusion-rgba` |
| `sim-ink-diffusion` | RGBA state packing | `sim-ink-diffusion-rgba` |
| `cellular-automata-3d` | RGBA ecosystem | `cellular-automata-rgba` |
| `sim-sand-dunes` | RGBA grain simulation | `sim-sand-dunes-rgba` |
| `sim-decay-system` | RGBA decay fields | `sim-decay-system-rgba` |

### CB-3: Convolution Post-Processor
| Target | Technique | New Shader Name |
|--------|-----------|-----------------|
| `quantum-foam` | bilateral filter | `quantum-foam-bilateral` |
| `neural-raymarcher` | Gabor texture | `neural-raymarcher-gabor` |
| `gravitational-lensing` | NLM artistic | `gravitational-lensing-nlm` |
| `tensor-flow-sculpting` | morphological | `tensor-flow-morphological` |
| `holographic-interferometry` | bilateral | `holographic-interferometry-bilateral` |

### CB-4: Mouse Physics Injector
| Target | Technique | New Shader Name |
|--------|-----------|-----------------|
| `sim-slime-mold-growth` | EM field | `sim-slime-mold-growth-em` |
| `hyper-tensor-fluid` | fluid coupling | `hyper-tensor-fluid-coupled` |
| `sim-volumetric-fake` | EM field | `sim-volumetric-fake-em` |
| `fractal-boids-field` | fluid coupling | `fractal-boids-field-coupled` |
| `multi-fractal-compositor` | gravitational lens | `multi-fractal-compositor-lens` |

---

## Rules for All Enhancement Agents
1. Create NEW shader files — do NOT overwrite existing Phase B shaders
2. Read the original Phase B shader as reference
3. Read the Phase C technique shader as reference
4. Combine them meaningfully — don't just copy-paste
5. Use standard AGENTS.md bindings and headers
6. Write JSON definitions for each new shader
7. Run `generate_shader_lists.js` after each batch

---

## Wave 2 Enhancement Assignments (Additional Targets)

### CB-5: Generative & Hybrid Enhancer
| Target | Technique | New Shader Name |
|--------|-----------|-----------------|
| `gen-xeno-botanical-synth-flora` | alpha-multi-state-ecosystem | `gen-xeno-botanical-ecosystem` |
| `gen-biomechanical-hive` | spec-quaternion-julia | `gen-biomechanical-hive-julia` |
| `gen-astro-kinetic-chrono-orrery` | spec-blackbody-thermal | `gen-astro-orrery-blackbody` |
| `gen-audio-spirograph` | mouse-julia-morph | `gen-audio-spirograph-julia` |
| `gen-raptor-mini` | conv-structure-tensor-flow | `gen-raptor-mini-flow` |

### CB-6: Alpha & Post-Process Enhancer
| Target | Technique | New Shader Name |
|--------|-----------|-----------------|
| `glass_refraction_alpha` | spec-prismatic-dispersion | `glass-refraction-prismatic` |
| `ink_dispersion_alpha` | conv-guided-filter-depth | `ink-dispersion-guided` |
| `particle_dreams_alpha` | alpha-hdr-bloom-chain | `particle-dreams-hdr` |
| `retro_phosphor_dream` | spec-blue-noise-stipple | `retro-phosphor-stipple` |
| `liquid_magnetic_ferro` | alpha-em-field-simulation | `liquid-magnetic-ferro-em` |

### CB-7: Flow & Multi-Pass Enhancer
| Target | Technique | New Shader Name |
|--------|-----------|-----------------|
| `sim-fluid-feedback-field` | mouse-fluid-coupling | `sim-fluid-feedback-coupled` |
| `audio-voronoi-displacement` | conv-gabor-texture-analyzer | `audio-voronoi-gabor` |
| `spectral-flow-sorting` | conv-structure-tensor-flow | `spectral-flow-structure` |
| `hybrid-spectral-sorting` | alpha-spectral-decompose | `hybrid-spectral-decomposed` |
| `aurora-rift-2` | spec-iridescence-engine | `aurora-rift-2-iridescence` |


---

## Wave 3 Enhancement Assignments (Expanded Coverage)

507 additional Phase B shaders identified. Selected high-value targets below.

### CB-8: Thermal & Atmospheric Enhancer
| Target | Technique | New Shader Name |
|--------|-----------|-----------------|
| `thermal-vision` | spec-blackbody-thermal | `thermal-vision-blackbody` |
| `thermal-touch` | spec-blackbody-thermal | `thermal-touch-blackbody` |
| `aerogel-smoke` | alpha-hdr-bloom-chain | `aerogel-smoke-hdr` |
| `aero-chromatics` | spec-prismatic-dispersion | `aero-chromatics-prismatic` |
| `black-hole` | spec-iridescence-engine | `black-hole-iridescence` |
| `bioluminescent` | spec-blackbody-thermal | `bioluminescent-blackbody` |
| `atmos_volumetric_fog` | alpha-depth-fog-volumetric | `atmos-fog-volumetric` |
| `aurora_borealis` | spec-iridescence-engine | `aurora-borealis-iridescence` |

### CB-9: Interactive Mouse Enhancer
| Target | Technique | New Shader Name |
|--------|-----------|-----------------|
| `block-distort-interactive` | mouse-electromagnetic-aurora | `block-distort-em` |
| `chromatic-focus-interactive` | mouse-fluid-coupling | `chromatic-focus-coupled` |
| `cmyk-halftone-interactive` | mouse-chromatic-explosion | `cmyk-halftone-explosion` |
| `bio-touch` | mouse-electromagnetic-aurora | `bio-touch-em` |
| `bubble-lens` | mouse-fluid-coupling | `bubble-lens-coupled` |
| `circuit-breaker` | mouse-chromatic-explosion | `circuit-breaker-explosion` |

### CB-10: Image Processing & Artistry Enhancer
| Target | Technique | New Shader Name |
|--------|-----------|-----------------|
| `anisotropic-kuwahara` | conv-non-local-means | `anisotropic-kuwahara-nlm` |
| `artistic_painterly_oil` | conv-bilateral-dream | `painterly-oil-bilateral` |
| `ascii-flow` | conv-structure-tensor-flow | `ascii-flow-structure` |
| `astral-kaleidoscope` | conv-morphological-erosion-dilation | `astral-kaleidoscope-morph` |
| `charcoal-rub` | conv-anisotropic-diffusion | `charcoal-rub-diffusion` |
| `blueprint-reveal` | conv-guided-filter-depth | `blueprint-reveal-guided` |

### CB-11: Simulation & Flocking RGBA Upgrader
| Target | Technique | New Shader Name |
|--------|-----------|-----------------|
| `boids` | alpha-multi-state-ecosystem | `boids-rgba-ecosystem` |
| `bio_lenia_continuous` | alpha-reaction-diffusion-rgba | `bio-lenia-rgba` |
| `wave-equation` | alpha-fluid-simulation-paint | `wave-equation-rgba-fluid` |
| `predator-prey` | alpha-multi-state-ecosystem | `predator-prey-rgba` |
| `nano-assembler` | alpha-crystal-growth-phase | `nano-assembler-crystal` |
| `photonic-caustics` | spec-iridescence-engine | `photonic-caustics-iridescence` |

### CB-12: Chroma & Spectral Enhancer
| Target | Technique | New Shader Name |
|--------|-----------|-----------------|
| `chroma-depth-tunnel` | spec-prismatic-dispersion | `chroma-depth-tunnel-prismatic` |
| `chroma-kinetic` | spec-blackbody-thermal | `chroma-kinetic-blackbody` |
| `chroma-lens` | spec-iridescence-engine | `chroma-lens-iridescence` |
| `chroma-threads` | conv-gabor-texture-analyzer | `chroma-threads-gabor` |
| `chroma-vortex` | mouse-fluid-coupling | `chroma-vortex-coupled` |
| `chromatic-crawler` | conv-structure-tensor-flow | `chromatic-crawler-structure` |
| `chromatic-focus` | conv-guided-filter-depth | `chromatic-focus-guided` |
| `chromatic-folds` | conv-bilateral-dream | `chromatic-folds-bilateral` |
| `chromatic-infection` | alpha-reaction-diffusion-rgba | `chromatic-infection-rgba` |
| `chromatic-shockwave` | mouse-electromagnetic-aurora | `chromatic-shockwave-em` |
| `chromatic-swirl` | mouse-fluid-coupling | `chromatic-swirl-coupled` |
| `chromatographic-separation` | alpha-spectral-decompose | `chromatographic-separation-spectral` |

