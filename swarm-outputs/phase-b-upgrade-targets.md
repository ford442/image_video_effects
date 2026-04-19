# Phase B Upgrade Targets

**Generated:** 2026-04-18
**Version:** 5.0 (COMPLETE — 100% library coverage)
**Evaluator:** Evaluator Swarm
**Total Targets:** 674
**Focus:** Mouse-driven interactivity (not audio reactivity)

## Changelog

- **v1.0:** Initial list (114 targets, 39 false positives)
- **v2.0:** Corrected false positives, mouse-depth classification (113 targets)
- **v3.0:** Expanded with basic-mouse enhancements (+119 = 232)
- **v4.0:** ALL remaining basic-mouse + large advanced shaders (+250 = 482)
- **v5.0:** COMPLETE sweep — every remaining shader added (+192 = 674)

## Bucket Summary

| Bucket | Count | Priority | Focus |
|--------|-------|----------|-------|
| Huge Refactors | 13 | P1 | Multi-pass split for >15KB shaders |
| Complex Upgrades | 348 | P2–P3 | 5–15KB shaders, enhance/optimize |
| Advanced Hybrids | 10 | P2 | New multi-technique mouse-driven shaders |
| Mouse-Interactive | 303 | P4–P5 | <5KB shaders, add/enhance mouse |

### Mouse Depth Breakdown

| Depth | Count | Meaning |
|-------|-------|---------|
| **none** | 124 | No mouse at all — add from scratch |
| **basic** | 343 | Reads position only — enhance with clicks/physics |
| **advanced** | 207 | Has clicks/physics — optimize/refine |

---

## 1. Huge Refactors (>15 KB)

| Priority | Shader | Size | Category | Mouse | Notes |
|----------|--------|------|----------|-------|-------|
| 1 | `liquid-optimized` | 21.9 KB | liquid-effects | ❌ | Multi-pass refactor. Mouse: none. |
| 1 | `spectrogram-displace` | 21.3 KB | image | ✅ | Multi-pass refactor. Mouse: advanced. |
| 1 | `digital-glitch` | 20.2 KB | image | △ | Multi-pass refactor. Mouse: basic. |
| 1 | `liquid` | 18.5 KB | image | ❌ | Add mouse from scratch. |
| 1 | `vortex` | 17.6 KB | image | ❌ | Add mouse from scratch. |
| 1 | `tensor-flow-sculpt` | 17.4 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 1 | `recursion-mirror-vortex` | 16.6 KB | artistic | △ | Enhance mouse: add click states, physics, spring following. |
| 1 | `chromatic-phase-inversion` | 16.5 KB | artistic | △ | Enhance mouse: add click states, physics, spring following. |
| 1 | `tensor-flow-sculpting` | 16.1 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 1 | `spectral-bleed-confine` | 15.9 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 1 | `gen-hyperbolic-tessellation` | 15.8 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 1 | `gen-chromatic-metamorphosis` | 15.4 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 1 | `scanline-tear` | 15.2 KB | retro-glitch | ❌ | Add mouse from scratch. |

---

## 2. Complex Upgrades (5–15 KB)

| Priority | Shader | Size | Category | Mouse | Notes |
|----------|--------|------|----------|-------|-------|
| 2 | `crt-tv` | 13.8 KB | retro-glitch | ❌ | Add mouse from scratch. |
| 2 | `vhs-tracking` | 13.5 KB | image | ❌ | Add mouse from scratch. |
| 2 | `infinite-zoom` | 12.9 KB | image | ❌ | Add mouse from scratch. |
| 2 | `aurora-rift-2-pass1` | 11.4 KB | lighting-effects | ❌ | Add mouse from scratch. |
| 2 | `aurora-rift-pass1` | 11.3 KB | lighting-effects | ❌ | Add mouse from scratch. |
| 2 | `wolfram-data-demo` | 11.3 KB | generative | ❌ | Add mouse from scratch. |
| 2 | `liquid-viscous` | 10.6 KB | image | ❌ | Add mouse from scratch. |
| 2 | `astral-veins` | 10.3 KB | image | ❌ | Add mouse from scratch. |
| 2 | `quantum-foam-pass1` | 10.3 KB | simulation | ❌ | Add mouse from scratch. |
| 2 | `chromatic-manifold` | 10.0 KB | image | ❌ | Add mouse from scratch. |
| 2 | `liquid-v1` | 9.5 KB | image | ❌ | Add mouse from scratch. |
| 2 | `gen-bismuth-crystal-citadel` | 9.3 KB | generative | ❌ | Add mouse from scratch. |
| 2 | `artistic_painterly_oil` | 9.2 KB | artistic | ❌ | Add mouse from scratch. |
| 2 | `gen-magnetic-field-lines` | 8.3 KB | generative | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `cellular-automata-3d` | 8.2 KB | generative | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `crystal-freeze` | 8.2 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `liquid-perspective` | 8.2 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `fractal-boids-field` | 8.1 KB | simulation | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `volumetric-cloud-nebula` | 8.1 KB | generative | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `hyper-tensor-fluid` | 8.0 KB | simulation | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `gen_grokcf_voronoi` | 7.9 KB | unknown | ❌ | Add mouse from scratch. MISSING JSON. |
| 2 | `gen-mycelium-network` | 7.9 KB | generative | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `quantum-foam-pass3` | 7.7 KB | simulation | ❌ | Add mouse from scratch. |
| 2 | `gen_quantum_foam` | 7.6 KB | generative | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `pp-tone-map` | 7.6 KB | post-processing | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `liquid-oil` | 7.6 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `physarum-grokcf1` | 7.5 KB | simulation | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `physarum-gemini` | 7.5 KB | simulation | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `gen_grok41_mandelbrot` | 7.4 KB | unknown | ❌ | Add mouse from scratch. MISSING JSON. |
| 2 | `pp-bloom` | 7.4 KB | post-processing | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `gemstone-fractures` | 7.4 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `gen-topology-flow` | 7.3 KB | generative | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `chromatic-folds-gemini` | 7.3 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `snow` | 7.3 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `hybrid-particle-fluid` | 7.2 KB | simulation | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `liquid-rgb` | 7.2 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `lidar` | 7.0 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `gen-velocity-bloom` | 6.9 KB | lighting-effects | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `gen-string-theory` | 6.9 KB | generative | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `hybrid-cyber-organic` | 6.8 KB | generative | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `liquid-fast` | 6.7 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `gen-bifurcation-diagram` | 6.7 KB | generative | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `gen-audio-spirograph` | 6.6 KB | generative | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `holographic-interferometry` | 6.6 KB | generative | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `radiating-displacement` | 6.6 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `hyperbolic-dreamweaver` | 6.6 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `liquid-rainbow` | 6.6 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `gen-temporal-motion-smear` | 6.5 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `liquid-viscous-grokcf1` | 6.5 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `green-tracer` | 6.4 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `aurora-rift-2` | 6.3 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `julia-warp` | 6.3 KB | distortion | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `gen-voronoi-crystal` | 6.2 KB | generative | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `liquid-glitch` | 6.2 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `hybrid-noise-kaleidoscope` | 6.1 KB | generative | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `gen-neural-fractal` | 6.0 KB | generative | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `digital-waves` | 5.9 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `sim-volumetric-fake` | 5.7 KB | lighting-effects | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `gen-quasicrystal` | 5.7 KB | generative | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `kimi_liquid_glass` | 5.6 KB | unknown | ❌ | Add mouse from scratch. MISSING JSON. |
| 2 | `sketch-reveal` | 5.4 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `pp-ssao` | 5.4 KB | post-processing | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `pp-sharpen` | 5.4 KB | post-processing | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `pp-vignette` | 5.4 KB | post-processing | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `galaxy` | 5.3 KB | unknown | ❌ | Add mouse from scratch. MISSING JSON. |
| 2 | `pp-chromatic` | 5.3 KB | post-processing | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `liquid-jelly` | 5.2 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `spectrum-bleed` | 5.1 KB | image | ❌ | Add/enhance mouse response. Current: none. |
| 2 | `pixelation-drift` | 5.1 KB | image | ❌ | Add mouse from scratch. |
| 2 | `chromatographic-separation` | 5.1 KB | simulation | ❌ | Add mouse from scratch. |
| 3 | `quantum-foam` | 20.1 KB | image | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `rgb-glitch-displacement` | 18.1 KB | retro-glitch | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `liquid-displacement` | 17.0 KB | liquid-effects | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `spectral-bleed-confinement` | 16.5 KB | artistic | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `gen-gravitational-strain` | 16.0 KB | generative | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `gen-inverse-mandelbrot` | 15.9 KB | generative | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `chromatic-crawler` | 15.0 KB | image | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `neural-resonance` | 14.6 KB | image | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `quantum-smear` | 14.4 KB | image | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `rainbow-cloud` | 14.2 KB | image | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `gen-holographic-data-core` | 14.1 KB | generative | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `chromatic-folds` | 13.9 KB | image | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `gen-art-deco-sky` | 13.4 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `pixel-sort-glitch` | 13.4 KB | distortion | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `gen_grok4_life` | 13.2 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 3 | `chromatic-folds-2` | 13.2 KB | image | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `stella-orbit` | 13.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `scan-distort` | 12.9 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `aurora-rift-2-pass2` | 12.6 KB | lighting-effects | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen-ethereal-anemone-bloom` | 12.3 KB | generative | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `datamosh` | 12.1 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `chromatic-focus` | 11.6 KB | artistic | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen-celestial-forge` | 11.6 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `aurora-rift-pass2` | 11.4 KB | lighting-effects | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `chromatic-manifold-2` | 11.4 KB | image | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `gen-biomechanical-hive` | 11.2 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `ethereal-swirl` | 11.2 KB | image | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `quantum-foam-pass2` | 11.2 KB | simulation | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `nebulous-dream` | 11.2 KB | image | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `gen-isometric-city` | 11.0 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen-liquid-crystal-hive-mind` | 10.8 KB | generative | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `gen-celestial-prism-orchid` | 10.8 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `glitch-pixel-sort` | 10.5 KB | image | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `gen_trails` | 10.5 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 3 | `aurora-rift` | 10.4 KB | image | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `fabric-step` | 10.3 KB | simulation | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `chromatic-infection` | 10.2 KB | image | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `neural-dreamscape` | 10.2 KB | image | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `liquid-zoom` | 10.2 KB | image | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `predator-prey` | 10.1 KB | generative | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `aurora-rift-gemini` | 10.1 KB | image | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `gen_orb` | 10.0 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 3 | `holographic-projection-gpt52` | 10.0 KB | visual-effects | ✅ | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| 3 | `photonic-caustics` | 10.0 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `bioluminescent` | 9.7 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `neon-edges` | 9.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `parallax-glow-compositor` | 9.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `phase-shift` | 9.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `prismatic-mosaic` | 9.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `matrix_digital_rain` | 9.6 KB | retro-glitch | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `nebula-gyroid` | 9.6 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `neon-edge-pulse` | 9.6 KB | visual-effects | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `parallax_depth_layers` | 9.6 KB | visual-effects | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `particle_dreams_alpha` | 9.6 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen-alien-flora` | 9.6 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `liquid-volumetric-zoom` | 9.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `byte-mosh` | 9.5 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `dla-crystals` | 9.4 KB | simulation | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `iridescent-oil-slick` | 9.1 KB | artistic | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen-brutalist-monument` | 9.0 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen_kimi_crystal` | 8.8 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 3 | `quantum-wormhole` | 8.7 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `poincare-tile` | 8.7 KB | geometric | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen-prismatic-bismuth-lattice` | 8.7 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `anisotropic-kuwahara` | 8.7 KB | artistic | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `astral-kaleidoscope` | 8.7 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen_grok41_plasma` | 8.6 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 3 | `astral-kaleidoscope-gemini` | 8.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `astral-kaleidoscope-grokcf1` | 8.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `glass_refraction_alpha` | 8.5 KB | distortion | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `crystal-illuminator` | 8.5 KB | interactive-mouse | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `kimi_flock_symphony` | 8.5 KB | generative | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen_mandelbulb_3d` | 8.4 KB | generative | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `liquid-warp` | 8.4 KB | interactive-mouse | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen-prismatic-fractal-dunes` | 8.4 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `multi-turing` | 8.2 KB | simulation | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `wave-equation` | 8.2 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `steamy-glass` | 8.1 KB | simulation | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `volumetric-rainbow-clouds` | 8.1 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `volumetric-depth-zoom` | 8.0 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen-neuro-cosmos` | 8.0 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `interactive_neural_swarm` | 8.0 KB | interactive-mouse | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `magnetic-dipole` | 8.0 KB | simulation | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen-quantum-neural-lace` | 8.0 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen-fractured-monolith` | 7.9 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen_grokcf_interference` | 7.9 KB | unknown | △ | Enhance mouse: add click states, physics, spring following. MISSING JSON. |
| 3 | `gen_grid` | 7.9 KB | unknown | △ | Enhance mouse: add click states, physics, spring following. MISSING JSON. |
| 3 | `voronoi-dynamics` | 7.9 KB | geometric | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen-auroral-ferrofluid-monolith` | 7.9 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen-abyssal-leviathan-scales` | 7.8 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `crystal-facets` | 7.8 KB | distortion | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `bismuth-crystallizer` | 7.7 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `vaporwave-horizon` | 7.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen-micro-cosmos` | 7.6 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `cosmic-flow` | 7.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen-holographic-plasma-geode` | 7.6 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `anamorphic-flare` | 7.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `boids` | 7.6 KB | simulation | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `distortion_gravitational_lens` | 7.5 KB | distortion | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `hybrid-spectral-sorting` | 7.5 KB | distortion | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `spectral-flow-sorting` | 7.5 KB | distortion | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `honey-melt` | 7.5 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen-obsidian-echo-chamber` | 7.5 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `cyber-terminal-ascii` | 7.4 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `audio_geometric_pulse` | 7.4 KB | geometric | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `liquid-time-warp` | 7.2 KB | interactive-mouse | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `log-polar-droste` | 7.2 KB | geometric | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen-hyper-dimensional-tesseract-labyrinth` | 7.2 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `liquid-touch` | 7.1 KB | interactive-mouse | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `sim-slime-mold-growth` | 7.1 KB | simulation | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `flow-sort` | 7.1 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `quantum-fractal` | 7.1 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `aerogel-smoke` | 7.1 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `liquid-smear` | 7.1 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen-cybernetic-ferro-coral` | 7.0 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `chromatic-reaction-diffusion` | 7.0 KB | artistic | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen-hyper-labyrinth` | 7.0 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `zipper-reveal` | 7.0 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `liquid-chrome-ripple` | 6.9 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `hybrid-magnetic-field` | 6.9 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `digital-moss` | 6.9 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `audio-voronoi-displacement` | 6.9 KB | distortion | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen_fluffy_raincloud` | 6.9 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 3 | `time-lag-map` | 6.9 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `hybrid-reaction-diffusion-glass` | 6.9 KB | simulation | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `radiating-haze` | 6.8 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gravity-lens` | 6.8 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `impasto-swirl` | 6.8 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `light-leaks` | 6.8 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `holographic-contour` | 6.8 KB | artistic | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `holographic-projection` | 6.8 KB | visual-effects | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `hybrid-sdf-plasma` | 6.8 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `ink_dispersion_alpha` | 6.8 KB | liquid-effects | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `liquid-prism-cascade` | 6.8 KB | artistic | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `liquid-swirl` | 6.8 KB | distortion | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `hybrid-chromatic-liquid` | 6.8 KB | distortion | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `kimi_nebula_depth` | 6.8 KB | unknown | △ | Enhance mouse: add click states, physics, spring following. MISSING JSON. |
| 3 | `particle-disperse` | 6.8 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `sim-decay-system` | 6.8 KB | artistic | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen_julia_set` | 6.8 KB | unknown | △ | Enhance mouse: add click states, physics, spring following. MISSING JSON. |
| 3 | `stellar-plasma` | 6.8 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen-singularity-forge` | 6.7 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen_rainbow_smoke` | 6.7 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 3 | `perspective-tilt` | 6.7 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `nano-repair` | 6.7 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen-prismatic-aether-loom` | 6.7 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `slime-drip` | 6.7 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `liquid-prism` | 6.7 KB | distortion | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `sim-ink-diffusion` | 6.7 KB | artistic | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `liquid_magnetic_ferro` | 6.6 KB | liquid-effects | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `data-stream-corruption` | 6.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `charcoal-rub` | 6.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `underwater_caustics` | 6.6 KB | lighting-effects | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `poly-art` | 6.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `vortex-prism` | 6.5 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `liquid_crystal_birefringence` | 6.5 KB | distortion | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `split-flap-display` | 6.5 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `sim-sand-dunes` | 6.5 KB | simulation | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `rgb-split-glitch` | 6.5 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen-neural-bioluminescence-matrix` | 6.5 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `encaustic-wax` | 6.5 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `liquid-mirror` | 6.4 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `crumpled-paper` | 6.4 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gravity-well` | 6.4 KB | distortion | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `physarum` | 6.4 KB | simulation | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `pixel-wind-chimes` | 6.4 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen-stellar-plasma-ouroboros` | 6.4 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `particle-swarm` | 6.4 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `raindrop-ripples` | 6.4 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `bio_lenia_continuous` | 6.4 KB | simulation | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `aurora_borealis` | 6.4 KB | generative | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `warp_drive` | 6.3 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 3 | `nano-assembler` | 6.3 KB | simulation | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `vortex-distortion` | 6.3 KB | distortion | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `ascii-decode` | 6.2 KB | interactive-mouse | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `cosmic-jellyfish` | 6.2 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `bubble-lens` | 6.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `infinite-fractal-feedback` | 6.2 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen-abyssal-chrono-coral` | 6.2 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `rgb-fluid` | 6.2 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `cmyk-halftone-interactive` | 6.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `rain` | 6.2 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen-hyper-refractive-rain-matrix` | 6.2 KB | generative | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `sim-smoke-trails` | 6.2 KB | simulation | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `hybrid-voronoi-glass` | 6.2 KB | distortion | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `chromatic-focus-interactive` | 6.2 KB | visual-effects | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `biomimetic-scales` | 6.1 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `rgb-ripple-waves` | 6.1 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `rgb-topology` | 6.1 KB | visual-effects | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `graphic_novel` | 6.1 KB | unknown | △ | Enhance mouse: add click states, physics, spring following. MISSING JSON. |
| 3 | `retro_phosphor_dream` | 6.1 KB | retro-glitch | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `vortex-drag` | 6.0 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `fabric-zipper` | 6.0 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `chromatic-swirl` | 6.0 KB | distortion | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `pin-art-3d` | 6.0 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `glass-shatter` | 6.0 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `hyper-space-jump` | 5.9 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `rgb-shift-brush` | 5.9 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `infinite-spiral-zoom` | 5.9 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `cyber-physical-portal` | 5.9 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `ink-bleed` | 5.9 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `rgb-iso-lines` | 5.9 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `cross-stitch` | 5.8 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `kintsugi-repair` | 5.8 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen-bioluminescent-aether-pulsar` | 5.8 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `crystal-refraction` | 5.8 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `ink-marbling` | 5.8 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `rgb-distance-split` | 5.8 KB | visual-effects | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `flip-matrix` | 5.7 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `infinite-zoom-lens` | 5.7 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen-magnetic-ferrofluid` | 5.7 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `rgb-ripple-distortion` | 5.7 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `glitch-cathedral` | 5.7 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `interactive-pcb-traces` | 5.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `temporal-echo` | 5.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `glitch-reveal` | 5.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `sim-heat-haze-field` | 5.6 KB | distortion | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `frosted-glass-lens` | 5.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen-quantum-aether-origami` | 5.6 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `interactive-film-burn` | 5.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `engraving-stipple` | 5.6 KB | artistic | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `rgb-delay-brush` | 5.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `glitch-ripple-drag` | 5.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen-fractal-clockwork` | 5.6 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `vortex-warp` | 5.5 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `viscous-drag` | 5.5 KB | liquid-effects | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `dynamic-lens-flares` | 5.5 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `cyber-slit-scan` | 5.5 KB | interactive-mouse | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `strip-scan-glitch` | 5.5 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `generative-psy-swirls` | 5.5 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen_hyper_warp` | 5.4 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 3 | `datamosh-brush` | 5.4 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `stipple-engraving` | 5.4 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `rotoscope-ink` | 5.4 KB | artistic | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `interactive-halftone-spin` | 5.4 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `digital-haze` | 5.4 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `sliding-tile-glitch` | 5.4 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen-chromodynamic-plasma-collider` | 5.4 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `rain-ripples` | 5.4 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `retro-gameboy` | 5.3 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `kimi_fractal_dreams` | 5.3 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 3 | `parallax-shift` | 5.3 KB | distortion | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `luminescent-glass-tiles` | 5.3 KB | distortion | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen_kimi_nebula` | 5.3 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 3 | `sequin-flip` | 5.3 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `neon-contour-drag` | 5.3 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `edge-glow-mouse` | 5.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `venetian-blinds` | 5.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `cyber-hex-armor` | 5.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `glass-bead-curtain` | 5.2 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `gen-crystalline-chrono-dyson` | 5.2 KB | generative | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `ascii-shockwave` | 5.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `chromatic-shockwave` | 5.2 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `paper-burn` | 5.2 KB | interactive-mouse | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `magma-fissure` | 5.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `voronoi-chaos` | 5.2 KB | distortion | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `cyber-rain-interactive` | 5.2 KB | retro-glitch | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `knitted-fabric` | 5.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `glass-brick-distortion` | 5.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen-graviton-plasma-lotus` | 5.2 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `voronoi-faceted-glass` | 5.1 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `kaleido-portal-interactive` | 5.1 KB | interactive-mouse | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `kimi_quantum_field` | 5.1 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 3 | `slinky-distort` | 5.1 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `neon-edge-reveal` | 5.1 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `generative-turing-veins` | 5.1 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `aero-chromatics` | 5.1 KB | simulation | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `block-distort-interactive` | 5.1 KB | interactive-mouse | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `cyber-magnifier` | 5.1 KB | interactive-mouse | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `glass-wall` | 5.1 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `gen-nebular-chrono-astrolabe` | 5.0 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `cyber-lens` | 5.0 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `glass-wipes` | 5.0 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `circuit-breaker` | 5.0 KB | interactive-mouse | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `rorschach-inkblot` | 5.0 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `prismatic-3d-compositor` | 5.0 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 3 | `voronoi-zoom-turbulence` | 5.0 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 3 | `sphere-projection` | 5.0 KB | image | △ | Enhance mouse: add click states, physics, spring following. |

---

## 3. Advanced Hybrid Creations (New Shaders)

| Priority | Shader | Category | Techniques | Notes |
|----------|--------|----------|------------|-------|
| 2 | `hyper-tensor-fluid` | advanced-hybrid | tensor_flow, navier_stokes, depth_aware | New creation: tensor_flow, navier_stokes, depth_aware |
| 2 | `neural-raymarcher` | advanced-hybrid | sdf_raymarching, neural_pattern, volumetric | New creation: sdf_raymarching, neural_pattern, volumetric |
| 2 | `chromatic-rd-cascade` | advanced-hybrid | reaction_diffusion, chromatic_aberration, feedback | New creation: reaction_diffusion, chromatic_aberration, feedback |
| 2 | `gravitational-lensing` | advanced-hybrid | physics_simulation, spacetime_distortion, raytracing | New creation: physics_simulation, spacetime_distortion, raytracing |
| 2 | `cellular-automata-3d` | advanced-hybrid | cellular_automata, 3d_texture, raymarching | New creation: cellular_automata, 3d_texture, raymarching |
| 2 | `spectral-flow-hybrid` | advanced-hybrid | pixel_sorting, optical_flow, spectral_analysis | New creation: pixel_sorting, optical_flow, spectral_analysis |
| 2 | `multi-fractal-compositor` | advanced-hybrid | mandelbrot, julia, lyapunov, hybrid_fractals | New creation: mandelbrot, julia, lyapunov, hybrid_fractals |
| 2 | `mouse-voronoi-displacement` | advanced-hybrid | voronoi, mouse_displacement, displacement_mapping | New creation: voronoi, mouse_displacement, displacement_mapping |
| 2 | `fractal-boids-field` | advanced-hybrid | boids_flocking, fractal_noise, vector_field | New creation: boids_flocking, fractal_noise, vector_field |
| 2 | `holographic-interferometry` | advanced-hybrid | interference_patterns, holography, depth_parallax | New creation: interference_patterns, holography, depth_parallax |

---

## 4. Mouse-Interactive Upgrades (<5 KB)

| Priority | Shader | Size | Category | Mouse | Notes |
|----------|--------|------|----------|-------|-------|
| 4 | `liquid-viscous-simple` | 4.9 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `atmos_volumetric_fog` | 4.9 KB | lighting-effects | ❌ | Add mouse interaction. Current: none. |
| 4 | `fractal-kaleidoscope` | 4.8 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `lenia` | 4.8 KB | simulation | ❌ | Add mouse interaction. Current: none. |
| 4 | `video-echo-chamber` | 4.8 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `gen-feedback-echo-chamber` | 4.8 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `reaction-diffusion` | 4.7 KB | simulation | ❌ | Add mouse interaction. Current: none. |
| 4 | `sine-wave` | 4.6 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `holographic-prism` | 4.6 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `digital-decay` | 4.5 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `neon-pulse` | 4.5 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `infinite-video-feedback` | 4.5 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `gen_grok4_perlin` | 4.4 KB | unknown | ❌ | Add mouse from scratch. MISSING JSON. |
| 4 | `neon-edge-radar` | 4.4 KB | interactive-mouse | ❌ | Add mouse interaction. Current: none. |
| 4 | `sim-fluid-feedback-field-pass3` | 4.3 KB | unknown | ❌ | Add mouse from scratch. MISSING JSON. |
| 4 | `holographic-glitch` | 4.3 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `holographic_interference` | 4.2 KB | lighting-effects | ❌ | Add mouse interaction. Current: none. |
| 4 | `hybrid-fractal-feedback` | 4.0 KB | generative | ❌ | Add mouse interaction. Current: none. |
| 4 | `prismatic-feedback-loop` | 4.0 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `holographic-edge-ripple` | 4.0 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `fire_smoke_volumetric` | 4.0 KB | simulation | ❌ | Add mouse interaction. Current: none. |
| 4 | `sim-fluid-feedback-field-pass1` | 3.9 KB | unknown | ❌ | Add mouse from scratch. MISSING JSON. |
| 4 | `neon-warp` | 3.9 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `neon-echo` | 3.9 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `optical-feedback` | 3.9 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `neon-topology` | 3.9 KB | visual-effects | ❌ | Add mouse interaction. Current: none. |
| 4 | `holographic-shatter` | 3.9 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `holographic-sticker` | 3.8 KB | visual-effects | ❌ | Add mouse interaction. Current: none. |
| 4 | `temporal_echo` | 3.8 KB | distortion | ❌ | Add mouse interaction. Current: none. |
| 4 | `liquid-metal` | 3.7 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `neon-pulse-stream` | 3.7 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `holographic-projection-failure` | 3.6 KB | retro-glitch | ❌ | Add mouse interaction. Current: none. |
| 4 | `neon-ripple-split` | 3.5 KB | interactive-mouse | ❌ | Add mouse interaction. Current: none. |
| 4 | `halftone` | 3.5 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `heat-haze-gpt52` | 3.5 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `luma-flow-field` | 3.5 KB | simulation | ❌ | Add mouse interaction. Current: none. |
| 4 | `neon-strings` | 3.4 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `phantom-lag` | 3.3 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `scanline-sorting` | 3.3 KB | image | ❌ | Add mouse interaction. Current: none. |
| 4 | `scan-distort-gpt52` | 3.2 KB | image | ❌ | Add mouse interaction. Current: none. |
| 5 | `kinetic_tiles` | 5.0 KB | unknown | △ | Enhance mouse: add click states, physics, spring following. MISSING JSON. |
| 5 | `hex-circuit` | 5.0 KB | visual-effects | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `cyber-organic` | 5.0 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `cosmic-web` | 5.0 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `refractive-bubbles` | 5.0 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `foil-impression` | 5.0 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `gen-cymatic-plasma-mandalas` | 4.9 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `lichtenberg-fractal` | 4.9 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `spectral-mesh` | 4.9 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `neon-contour-interactive` | 4.9 KB | artistic | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `molten-glass` | 4.8 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `glass-brick-wall` | 4.8 KB | distortion | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `quantum-superposition` | 4.8 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `gen-superfluid-quantum-foam` | 4.8 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `ascii-lens` | 4.8 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `gen-celestial-glass-tornado` | 4.8 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `x-ray-reveal` | 4.8 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `spectral-vortex` | 4.8 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `divine-light` | 4.8 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `gen-silica-tsunami` | 4.8 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `interactive-voronoi-web` | 4.8 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `refraction-shards` | 4.8 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `solarize-warp` | 4.8 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `triangle-mosaic` | 4.8 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `breathing-kaleidoscope` | 4.7 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `color-blindness` | 4.7 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `voxel-depth-sort` | 4.7 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `rain-lens-wipe` | 4.7 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `bubble-chamber` | 4.7 KB | generative | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `lens-flare-brush` | 4.7 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `predator-camouflage` | 4.7 KB | distortion | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `temporal-rift` | 4.7 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `quantum-flux` | 4.7 KB | interactive-mouse | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `gen-neuro-kinetic-bloom` | 4.7 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `interactive-glitch-cubes` | 4.7 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `phosphor-magnifier` | 4.7 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `voronoi-light` | 4.6 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `ascii-flow` | 4.6 KB | retro-glitch | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `neon-edge-diffusion` | 4.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `pixel-storm` | 4.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `pixel-rain` | 4.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `neon-pulse-edge` | 4.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `magnetic-luma-sort` | 4.6 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `frost-reveal` | 4.6 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `voronoi-glass` | 4.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `bayer-dither-interactive` | 4.6 KB | retro-glitch | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `adaptive-mosaic` | 4.6 KB | geometric | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `gen-lenia-2` | 4.5 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `ambient-liquid` | 4.5 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `voronoi-shatter` | 4.5 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `neon-light` | 4.5 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `flux-core` | 4.5 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `iso-hills` | 4.5 KB | artistic | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `bubble-wrap` | 4.5 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `interactive-ripple` | 4.4 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `magnetic-rgb` | 4.4 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `energy-shield` | 4.4 KB | interactive-mouse | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `neon-fluid-warp` | 4.4 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `radial-hex-lens` | 4.4 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `cyber-trace` | 4.4 KB | interactive-mouse | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `rainbow-vector-field` | 4.4 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `vinyl-scratch` | 4.3 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `crt-phosphor-decay` | 4.3 KB | retro-glitch | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `chroma-lens` | 4.3 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `signal-modulation` | 4.3 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `tilt-shift` | 4.3 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `cyber-focus` | 4.3 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `spectral-glitch-sort` | 4.3 KB | retro-glitch | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `neon-poly-grid` | 4.3 KB | geometric | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `ferrofluid` | 4.3 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `black-hole` | 4.3 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `fluid-grid` | 4.3 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `psychedelic-noise-flow` | 4.3 KB | interactive-mouse | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `digital-reveal` | 4.3 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `dimension-slicer` | 4.3 KB | distortion | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `plastic-bricks` | 4.3 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `interactive-kuwahara` | 4.3 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `data-slicer` | 4.2 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `optical-illusion-spin` | 4.2 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `motion-heatmap` | 4.2 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `mouse-gravity` | 4.2 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `chroma-threads` | 4.2 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `luma-glass` | 4.2 KB | distortion | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `cyber-glitch-hologram` | 4.2 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `digital-compression` | 4.2 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `electric-contours` | 4.2 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `reality-tear` | 4.2 KB | interactive-mouse | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `chronos-brush` | 4.2 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `vhs-jog` | 4.2 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `gen_cyclic_automaton` | 4.2 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 5 | `interactive-glitch` | 4.2 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `luma-refraction` | 4.2 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `neon-flashlight` | 4.2 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `origami-fold` | 4.1 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `luma-velocity-melt` | 4.1 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `gen_reaction_diffusion` | 4.1 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 5 | `sim-fluid-feedback-field-pass2` | 4.1 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 5 | `luma-smear-interactive` | 4.1 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `ascii-glyph` | 4.1 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `night-vision-scope` | 4.1 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `cyber-rain` | 4.1 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `quantum-prism` | 4.1 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `luma-topography` | 4.1 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `hex-lens` | 4.1 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `liquid-lens` | 4.1 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `gen-ethereal-quantum-medusa` | 4.1 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `gen-kinetic-neo-brutalist-megastructure` | 4.1 KB | generative | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `ring_slicer` | 4.1 KB | unknown | △ | Enhance mouse: add click states, physics, spring following. MISSING JSON. |
| 5 | `kimi_chromatic_warp` | 4.0 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 5 | `hex-pulse` | 4.0 KB | image | △ | Enhance mouse: add click-triggered effects. |
| 5 | `magnetic-chroma` | 4.0 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `interactive-origami` | 4.0 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `refraction-tunnel` | 4.0 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `matrix-curtain` | 4.0 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `luma-force` | 4.0 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `cyber-grid-pulse` | 4.0 KB | visual-effects | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `cyber-scan` | 4.0 KB | visual-effects | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `paper-cutout` | 4.0 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `reactive-glass-grid` | 4.0 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `liquid-warp-interactive` | 4.0 KB | distortion | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `magnetic-ring` | 4.0 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `elastic-surface` | 4.0 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `pixel-sort-explorer` | 4.0 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `pixel-reveal` | 4.0 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `mirror-dimension` | 3.9 KB | artistic | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `interactive-voronoi-lens` | 3.9 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `complex-exponent-warp` | 3.9 KB | distortion | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `motion-revealer` | 3.9 KB | interactive-mouse | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `fractal-noise-dissolve` | 3.9 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `codebreaker-reveal` | 3.9 KB | interactive-mouse | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `neural-nexus` | 3.9 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `directional-blur-wipe` | 3.9 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `pixel-explode` | 3.9 KB | interactive-mouse | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `blueprint-reveal` | 3.9 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `gen_capabilities` | 3.9 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 5 | `contour-flow` | 3.9 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `interactive-emboss` | 3.9 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `gamma-ray-burst` | 3.9 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `hypnotic-spiral` | 3.9 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `kaleido-scope` | 3.9 KB | geometric | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `halftone-reveal` | 3.8 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `spirograph-reveal` | 3.8 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `navier-stokes-dye` | 3.8 KB | simulation | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `spectral-smear` | 3.8 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `data-moshing` | 3.8 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `split-dimension` | 3.8 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `temporal-distortion-field` | 3.8 KB | distortion | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `chroma-vortex` | 3.8 KB | visual-effects | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `moire-interference` | 3.8 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `interactive-pixel-wind` | 3.7 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `ripple-blocks` | 3.7 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `fiber-optic-weave` | 3.7 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `scanline-drift` | 3.7 KB | retro-glitch | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `speed-lines-focus` | 3.7 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `cyber-halftone-scanner` | 3.7 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `circular-pixelate` | 3.7 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `fractal-glass-distort` | 3.7 KB | distortion | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `data-stream` | 3.7 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `bio-touch` | 3.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `heat-haze` | 3.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `prism-displacement` | 3.6 KB | distortion | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `steampunk-gear-lens` | 3.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `radial-slit-scan` | 3.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `gen_wave_equation` | 3.6 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 5 | `spectral-rain` | 3.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `scan-slice` | 3.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `magnetic-pixels` | 3.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `cursor-aura` | 3.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `stipple-render` | 3.6 KB | artistic | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `alucinate` | 3.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `luminance-wind` | 3.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `interactive-zoom-blur` | 3.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `quantum-tunnel-interactive` | 3.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `sonar-pulse` | 3.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `frosty-window` | 3.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `spectral-distortion` | 3.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `laser-burn` | 3.6 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `quantum-cursor` | 3.6 KB | interactive-mouse | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `interactive-rgb-split` | 3.6 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `magnetic-edge` | 3.6 KB | interactive-mouse | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `thermal-vision` | 3.5 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `pixel-focus` | 3.5 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `focal-pixelate` | 3.5 KB | interactive-mouse | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `kimi_spotlight` | 3.5 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 5 | `ion-stream` | 3.5 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `chroma-kinetic` | 3.5 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `mouse-pixel-sort` | 3.5 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `vhs-tracking-mouse` | 3.5 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `interactive-glitch-brush` | 3.5 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `crt-clear-zone` | 3.5 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `spectral-slit-scan` | 3.5 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `dynamic-halftone` | 3.5 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `hex-mosaic` | 3.5 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `wave-halftone` | 3.5 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `polka-wave` | 3.5 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `kimi_ripple_touch` | 3.5 KB | unknown | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| 5 | `velvet-vortex` | 3.5 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `luma-magnetism` | 3.5 KB | interactive-mouse | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `melting-oil` | 3.5 KB | simulation | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `luma-slice-interactive` | 3.4 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `fractal-image-surf` | 3.4 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `glitch-slice-mirror` | 3.4 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `pixel-sort-radial` | 3.4 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `quad-mirror` | 3.4 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `pixel-stretch-interactive` | 3.4 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `volumetric-god-rays` | 3.4 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `kinetic-dispersion` | 3.4 KB | interactive-mouse | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `spectral-waves` | 3.4 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `virtual-lens` | 3.4 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `chroma-depth-tunnel` | 3.4 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `luma-melt-interactive` | 3.4 KB | liquid-effects | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `pixel-drag-smear` | 3.4 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `elastic-strip` | 3.4 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `quantum-field-visualizer` | 3.4 KB | visual-effects | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `cyber-lattice` | 3.4 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `voronoi` | 3.3 KB | geometric | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `xerox-degrade` | 3.3 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `vertical-slice-wave` | 3.3 KB | interactive-mouse | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `data-scanner` | 3.3 KB | visual-effects | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `thermal-touch` | 3.3 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `quantized-ripples` | 3.3 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `cyber-ripples` | 3.3 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `stereoscopic-3d` | 3.3 KB | interactive-mouse | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `directional-glitch` | 3.3 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `divine-light-gpt52` | 3.3 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `neon-cursor-trace` | 3.3 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `pixel-scattering` | 3.3 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `polka-dot-reveal` | 3.3 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `voxel-grid` | 3.3 KB | visual-effects | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `magnetic-interference` | 3.3 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `spectral-brush` | 3.3 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `oscilloscope-overlay` | 3.3 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `kaleido-scope-grokcf1` | 3.3 KB | geometric | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `quantum-ripples` | 3.3 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `scanline-wave` | 3.2 KB | interactive-mouse | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `echo-ripple` | 3.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `polar-warp-interactive` | 3.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `tesseract-fold` | 3.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `page-curl-interactive` | 3.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `pixelate-blast` | 3.2 KB | retro-glitch | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `tile-twist` | 3.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `spiral-lens` | 3.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `double-exposure` | 3.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `mosaic-reveal` | 3.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `chromatic-mosaic-projector` | 3.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `chrono-slit-scan` | 3.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `digital-lens` | 3.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `crt-magnet` | 3.2 KB | image | △ | Enhance mouse: add click states, physics, spring following. |
| 5 | `pixel-depth-sort` | 3.1 KB | image | △ | Add mouse interaction. Current: basic. |
| 5 | `phosphor-decay` | 3.1 KB | visual-effects | △ | Add mouse interaction. Current: basic. |
| 5 | `pixel-sand` | 3.1 KB | image | △ | Add mouse interaction. Current: basic. |
| 5 | `luma-pixel-sort` | 3.1 KB | artistic | △ | Add mouse interaction. Current: basic. |
| 5 | `interactive-magnetic-ripple` | 3.1 KB | image | △ | Add mouse interaction. Current: basic. |
| 5 | `data-slicer-interactive` | 3.1 KB | interactive-mouse | △ | Add mouse interaction. Current: basic. |
| 5 | `pixel-stretch-cross` | 3.1 KB | image | △ | Add mouse interaction. Current: basic. |
| 5 | `hyper-chromatic-delay` | 3.1 KB | image | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `sonic-boom` | 3.1 KB | distortion | △ | Add mouse interaction. Current: basic. |
| 5 | `mirror-drag` | 3.1 KB | interactive-mouse | ✅ | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| 5 | `signal-tuner` | 3.1 KB | image | △ | Add mouse interaction. Current: basic. |
| 5 | `waveform-glitch` | 3.0 KB | image | △ | Add mouse interaction. Current: basic. |
| 5 | `temporal-rgb-smear` | 3.0 KB | image | △ | Add mouse interaction. Current: basic. |
| 5 | `elastic-chromatic` | 3.0 KB | image | △ | Add mouse interaction. Current: basic. |
| 5 | `bitonic-sort` | 3.0 KB | image | △ | Add mouse interaction. Current: basic. |

---

## Legend

- **❌** = No mouse usage — add from scratch
- **△** = Basic mouse (position only) — enhance with clicks, physics, spring
- **✅** = Advanced mouse — optimize/refine performance and alpha
