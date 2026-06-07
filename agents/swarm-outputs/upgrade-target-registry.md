# Living Master Upgrade Target Registry

**Generated:** 2026-04-18
**Evaluator:** Evaluator Swarm
**Purpose:** Central registry tracking all shader upgrade targets across Phase A, Phase B, and Phase C.

---

## Stats Dashboard

| Metric | Value |
|--------|-------|
| **Total Library Shaders** | 715 |
| **Phase A Completed** | 43/81 (53.1%) |
| **Phase B Pending** | 674/674 (100.0%) |
| **Shaders With Mouse** | 589 (82.4%) |
| **Shaders Without Mouse** | 126 (17.6%) |

### Phase A Grade Distribution

| Grade | Count |
|-------|-------|
| A | 0 |
| B | 41 |
| C | 2 |
| D | 0 |
| F | 0 |

### Phase B Bucket Summary

| Bucket | Count | Priority Range |
|--------|-------|----------------|
| Huge Refactors | 13 | P1 |
| Complex Upgrades | 348 | P2–P3 |
| Advanced Hybrids | 10 | P2 |
| Mouse-Interactive | 303 | P4–P5 |

### Phase B Mouse Depth Breakdown

| Depth | Count | Meaning |
|-------|-------|---------|
| **none** | 124 | No mouse at all — add from scratch |
| **basic** | 343 | Reads position only — enhance with clicks/physics |
| **advanced** | 207 | Has clicks/physics — optimize/refine |

---

## Master Summary Table

| Shader ID | Category | Size | Phase | Bucket | Status | Score | Mouse | Notes |
|-----------|----------|------|-------|--------|--------|-------|-------|-------|
| `gen-xeno-botanical-synth-flora` | generative | 3.9 KB | A | — | completed | 85 | — | Grade B |
| `gen-supernova-remnant` | generative | 7.4 KB | A | — | completed | 85 | — | Grade B |
| `rgb-glitch-trail` | image | 2.9 KB | A | — | completed | 82 | — | Grade B |
| `chroma-shift-grid` | image | 2.9 KB | A | — | completed | 82 | — | Grade B |
| `selective-color` | image | 2.9 KB | A | — | completed | 82 | — | Grade B |
| `temporal-slit-paint` | image | 2.8 KB | A | — | completed | 82 | — | Grade B |
| `signal-noise` | image | 3.1 KB | A | — | completed | 82 | — | Grade B |
| `sonic-distortion` | image | 3.2 KB | A | — | completed | 82 | — | Grade B |
| `galaxy-compute` | image | 3.2 KB | A | — | completed | 82 | — | Grade B |
| `radial-rgb` | interactive-mouse | 3.2 KB | A | — | completed | 82 | — | Grade B |
| `luma-echo-warp` | interactive-mouse | 3.2 KB | A | — | completed | 82 | — | Grade B |
| `gen-astro-kinetic-chrono-orrery` | generative | 4.1 KB | A | — | completed | 82 | — | Grade B |
| `gen-raptor-mini` | generative | 4.0 KB | A | — | completed | 82 | — | Grade B |
| `gen-cosmic-web-filament` | generative | 3.9 KB | A | — | completed | 82 | — | Grade B |
| `cymatic-sand` | generative | 4.0 KB | A | — | completed | 82 | — | Grade B |
| `gen-vitreous-chrono-chandelier` | generative | 4.3 KB | A | — | completed | 82 | — | Grade B |
| `gen-crystal-caverns` | generative | 4.4 KB | A | — | completed | 82 | — | Grade B |
| `gen-quantum-mycelium` | generative | 7.0 KB | A | — | completed | 82 | — | Grade B |
| `gen-stellar-web-loom` | generative | 6.8 KB | A | — | completed | 82 | — | Grade B |
| `gen-cyber-terminal` | generative | 9.6 KB | A | — | completed | 82 | — | Grade B |
| `gen-bioluminescent-abyss` | generative | 12.0 KB | A | — | completed | 82 | — | Grade B |
| `gen-chronos-labyrinth` | generative | 14.1 KB | A | — | completed | 82 | — | Grade B |
| `gen-quantum-superposition` | generative | 17.5 KB | A | — | completed | 82 | — | Grade B |
| `interactive-fisheye` | image | 2.7 KB | A | — | completed | 82 | — | Grade B |
| `radial-blur` | image | 2.7 KB | A | — | completed | 82 | — | Grade B |
| `swirling-void` | image | 2.8 KB | A | — | completed | 82 | — | Grade B |
| `static-reveal` | image | 3.2 KB | A | — | completed | 82 | — | Grade B |
| `entropy-grid` | image | 2.7 KB | A | — | completed | 82 | — | Grade B |
| `digital-mold` | image | 3.2 KB | A | — | completed | 82 | — | Grade B |
| `pixel-sorter` | image | 3.0 KB | A | — | completed | 82 | — | Grade B |
| `magnetic-field` | image | 3.2 KB | A | — | completed | 82 | — | Grade B |
| `kaleidoscope` | image | 3.4 KB | A | — | completed | 82 | — | Grade B |
| `synthwave-grid-warp` | image | 2.9 KB | A | — | completed | 82 | — | Grade B |
| `sonar-reveal` | interactive-mouse | 3.3 KB | A | — | completed | 82 | — | Grade B |
| `concentric-spin` | image | 3.0 KB | A | — | completed | 82 | — | Grade B |
| `interactive-fresnel` | visual-effects | 3.2 KB | A | — | completed | 82 | — | Grade B |
| `time-slit-scan` | visual-effects | 2.6 KB | A | — | completed | 82 | — | Grade B |
| `double-exposure-zoom` | image | 2.8 KB | A | — | completed | 82 | — | Grade B |
| `velocity-field-paint` | interactive-mouse | 3.0 KB | A | — | completed | 82 | — | Grade B |
| `pixel-repel` | interactive-mouse | 3.2 KB | A | — | completed | 82 | — | Grade B |
| `lighthouse-reveal` | image | 3.2 KB | A | — | completed | 82 | — | Grade B |
| `echo-trace` | artistic | 2.9 KB | A | — | completed | 73 | — | Grade C |
| `gen_psychedelic_spiral` | unknown | 4.3 KB | A | — | completed | 69 | — | Grade C |
| `liquid-optimized` | liquid-effects | 21.9 KB | B | huge | pending | — | none | Multi-pass refactor. Mouse: none. |
| `spectrogram-displace` | image | 21.3 KB | B | huge | pending | — | advanced | Multi-pass refactor. Mouse: advanced. |
| `digital-glitch` | image | 20.2 KB | B | huge | pending | — | basic | Multi-pass refactor. Mouse: basic. |
| `liquid` | image | 18.5 KB | B | huge | pending | — | none | Add mouse from scratch. |
| `vortex` | image | 17.6 KB | B | huge | pending | — | none | Add mouse from scratch. |
| `tensor-flow-sculpt` | unknown | 17.4 KB | B | huge | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `recursion-mirror-vortex` | artistic | 16.6 KB | B | huge | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `chromatic-phase-inversion` | artistic | 16.5 KB | B | huge | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `tensor-flow-sculpting` | image | 16.1 KB | B | huge | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `spectral-bleed-confine` | unknown | 15.9 KB | B | huge | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `gen-hyperbolic-tessellation` | generative | 15.8 KB | B | huge | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-chromatic-metamorphosis` | generative | 15.4 KB | B | huge | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `scanline-tear` | retro-glitch | 15.2 KB | B | huge | pending | — | none | Add mouse from scratch. |
| `crt-tv` | retro-glitch | 13.8 KB | B | complex | pending | — | none | Add mouse from scratch. |
| `vhs-tracking` | image | 13.5 KB | B | complex | pending | — | none | Add mouse from scratch. |
| `infinite-zoom` | image | 12.9 KB | B | complex | pending | — | none | Add mouse from scratch. |
| `aurora-rift-2-pass1` | lighting-effects | 11.4 KB | B | complex | pending | — | none | Add mouse from scratch. |
| `aurora-rift-pass1` | lighting-effects | 11.3 KB | B | complex | pending | — | none | Add mouse from scratch. |
| `wolfram-data-demo` | generative | 11.3 KB | B | complex | pending | — | none | Add mouse from scratch. |
| `liquid-viscous` | image | 10.6 KB | B | complex | pending | — | none | Add mouse from scratch. |
| `astral-veins` | image | 10.3 KB | B | complex | pending | — | none | Add mouse from scratch. |
| `quantum-foam-pass1` | simulation | 10.3 KB | B | complex | pending | — | none | Add mouse from scratch. |
| `chromatic-manifold` | image | 10.0 KB | B | complex | pending | — | none | Add mouse from scratch. |
| `liquid-v1` | image | 9.5 KB | B | complex | pending | — | none | Add mouse from scratch. |
| `gen-bismuth-crystal-citadel` | generative | 9.3 KB | B | complex | pending | — | none | Add mouse from scratch. |
| `artistic_painterly_oil` | artistic | 9.2 KB | B | complex | pending | — | none | Add mouse from scratch. |
| `gen-magnetic-field-lines` | generative | 8.3 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `cellular-automata-3d` | generative | 8.2 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `crystal-freeze` | image | 8.2 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `liquid-perspective` | image | 8.2 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `fractal-boids-field` | simulation | 8.1 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `volumetric-cloud-nebula` | generative | 8.1 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `hyper-tensor-fluid` | simulation | 8.0 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `gen_grokcf_voronoi` | unknown | 7.9 KB | B | complex | pending | — | none | Add mouse from scratch. MISSING JSON. |
| `gen-mycelium-network` | generative | 7.9 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `quantum-foam-pass3` | simulation | 7.7 KB | B | complex | pending | — | none | Add mouse from scratch. |
| `gen_quantum_foam` | generative | 7.6 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `pp-tone-map` | post-processing | 7.6 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `liquid-oil` | image | 7.6 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `physarum-grokcf1` | simulation | 7.5 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `physarum-gemini` | simulation | 7.5 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `gen_grok41_mandelbrot` | unknown | 7.4 KB | B | complex | pending | — | none | Add mouse from scratch. MISSING JSON. |
| `pp-bloom` | post-processing | 7.4 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `gemstone-fractures` | image | 7.4 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `gen-topology-flow` | generative | 7.3 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `chromatic-folds-gemini` | image | 7.3 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `snow` | image | 7.3 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `hybrid-particle-fluid` | simulation | 7.2 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `liquid-rgb` | image | 7.2 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `lidar` | image | 7.0 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `gen-velocity-bloom` | lighting-effects | 6.9 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `gen-string-theory` | generative | 6.9 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `hybrid-cyber-organic` | generative | 6.8 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `liquid-fast` | image | 6.7 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `gen-bifurcation-diagram` | generative | 6.7 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `gen-audio-spirograph` | generative | 6.6 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `holographic-interferometry` | generative | 6.6 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `radiating-displacement` | image | 6.6 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `hyperbolic-dreamweaver` | image | 6.6 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `liquid-rainbow` | image | 6.6 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `gen-temporal-motion-smear` | image | 6.5 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `liquid-viscous-grokcf1` | image | 6.5 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `green-tracer` | image | 6.4 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `aurora-rift-2` | image | 6.3 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `julia-warp` | distortion | 6.3 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `gen-voronoi-crystal` | generative | 6.2 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `liquid-glitch` | image | 6.2 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `hybrid-noise-kaleidoscope` | generative | 6.1 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `gen-neural-fractal` | generative | 6.0 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `digital-waves` | image | 5.9 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `sim-volumetric-fake` | lighting-effects | 5.7 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `gen-quasicrystal` | generative | 5.7 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `kimi_liquid_glass` | unknown | 5.6 KB | B | complex | pending | — | none | Add mouse from scratch. MISSING JSON. |
| `sketch-reveal` | image | 5.4 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `pp-ssao` | post-processing | 5.4 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `pp-sharpen` | post-processing | 5.4 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `pp-vignette` | post-processing | 5.4 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `galaxy` | unknown | 5.3 KB | B | complex | pending | — | none | Add mouse from scratch. MISSING JSON. |
| `pp-chromatic` | post-processing | 5.3 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `liquid-jelly` | image | 5.2 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `spectrum-bleed` | image | 5.1 KB | B | complex | pending | — | none | Add/enhance mouse response. Current: none. |
| `pixelation-drift` | image | 5.1 KB | B | complex | pending | — | none | Add mouse from scratch. |
| `chromatographic-separation` | simulation | 5.1 KB | B | complex | pending | — | none | Add mouse from scratch. |
| `quantum-foam` | image | 20.1 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `rgb-glitch-displacement` | retro-glitch | 18.1 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `liquid-displacement` | liquid-effects | 17.0 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `spectral-bleed-confinement` | artistic | 16.5 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `gen-gravitational-strain` | generative | 16.0 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `gen-inverse-mandelbrot` | generative | 15.9 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `chromatic-crawler` | image | 15.0 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `neural-resonance` | image | 14.6 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `quantum-smear` | image | 14.4 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `rainbow-cloud` | image | 14.2 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `gen-holographic-data-core` | generative | 14.1 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `chromatic-folds` | image | 13.9 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `gen-art-deco-sky` | generative | 13.4 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `pixel-sort-glitch` | distortion | 13.4 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `gen_grok4_life` | unknown | 13.2 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `chromatic-folds-2` | image | 13.2 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `stella-orbit` | image | 13.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `scan-distort` | image | 12.9 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `aurora-rift-2-pass2` | lighting-effects | 12.6 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen-ethereal-anemone-bloom` | generative | 12.3 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `datamosh` | image | 12.1 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `chromatic-focus` | artistic | 11.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-celestial-forge` | generative | 11.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `aurora-rift-pass2` | lighting-effects | 11.4 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `chromatic-manifold-2` | image | 11.4 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `gen-biomechanical-hive` | generative | 11.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `ethereal-swirl` | image | 11.2 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `quantum-foam-pass2` | simulation | 11.2 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `nebulous-dream` | image | 11.2 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `gen-isometric-city` | generative | 11.0 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-liquid-crystal-hive-mind` | generative | 10.8 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `gen-celestial-prism-orchid` | generative | 10.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `glitch-pixel-sort` | image | 10.5 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `gen_trails` | unknown | 10.5 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `aurora-rift` | image | 10.4 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `fabric-step` | simulation | 10.3 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `chromatic-infection` | image | 10.2 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `neural-dreamscape` | image | 10.2 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `liquid-zoom` | image | 10.2 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `predator-prey` | generative | 10.1 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `aurora-rift-gemini` | image | 10.1 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `gen_orb` | unknown | 10.0 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `holographic-projection-gpt52` | visual-effects | 10.0 KB | B | complex | pending | — | advanced | Optimize/refactor. Already has advanced mouse — focus on performance/alpha. |
| `photonic-caustics` | image | 10.0 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `bioluminescent` | image | 9.7 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `neon-edges` | image | 9.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `parallax-glow-compositor` | image | 9.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `phase-shift` | image | 9.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `prismatic-mosaic` | image | 9.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `matrix_digital_rain` | retro-glitch | 9.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `nebula-gyroid` | generative | 9.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `neon-edge-pulse` | visual-effects | 9.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `parallax_depth_layers` | visual-effects | 9.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `particle_dreams_alpha` | generative | 9.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-alien-flora` | generative | 9.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `liquid-volumetric-zoom` | image | 9.6 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `byte-mosh` | image | 9.5 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `dla-crystals` | simulation | 9.4 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `iridescent-oil-slick` | artistic | 9.1 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-brutalist-monument` | generative | 9.0 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen_kimi_crystal` | unknown | 8.8 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `quantum-wormhole` | image | 8.7 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `poincare-tile` | geometric | 8.7 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-prismatic-bismuth-lattice` | generative | 8.7 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `anisotropic-kuwahara` | artistic | 8.7 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `astral-kaleidoscope` | image | 8.7 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen_grok41_plasma` | unknown | 8.6 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `astral-kaleidoscope-gemini` | image | 8.6 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `astral-kaleidoscope-grokcf1` | image | 8.6 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `glass_refraction_alpha` | distortion | 8.5 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `crystal-illuminator` | interactive-mouse | 8.5 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `kimi_flock_symphony` | generative | 8.5 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen_mandelbulb_3d` | generative | 8.4 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `liquid-warp` | interactive-mouse | 8.4 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen-prismatic-fractal-dunes` | generative | 8.4 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `multi-turing` | simulation | 8.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `wave-equation` | image | 8.2 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `steamy-glass` | simulation | 8.1 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `volumetric-rainbow-clouds` | image | 8.1 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `volumetric-depth-zoom` | image | 8.0 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen-neuro-cosmos` | generative | 8.0 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `interactive_neural_swarm` | interactive-mouse | 8.0 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `magnetic-dipole` | simulation | 8.0 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen-quantum-neural-lace` | generative | 8.0 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-fractured-monolith` | generative | 7.9 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen_grokcf_interference` | unknown | 7.9 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. MISSING JSON. |
| `gen_grid` | unknown | 7.9 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. MISSING JSON. |
| `voronoi-dynamics` | geometric | 7.9 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen-auroral-ferrofluid-monolith` | generative | 7.9 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-abyssal-leviathan-scales` | generative | 7.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `crystal-facets` | distortion | 7.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `bismuth-crystallizer` | image | 7.7 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `vaporwave-horizon` | image | 7.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-micro-cosmos` | generative | 7.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `cosmic-flow` | image | 7.6 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen-holographic-plasma-geode` | generative | 7.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `anamorphic-flare` | image | 7.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `boids` | simulation | 7.6 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `distortion_gravitational_lens` | distortion | 7.5 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `hybrid-spectral-sorting` | distortion | 7.5 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `spectral-flow-sorting` | distortion | 7.5 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `honey-melt` | image | 7.5 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-obsidian-echo-chamber` | generative | 7.5 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `cyber-terminal-ascii` | image | 7.4 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `audio_geometric_pulse` | geometric | 7.4 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `liquid-time-warp` | interactive-mouse | 7.2 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `log-polar-droste` | geometric | 7.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-hyper-dimensional-tesseract-labyrinth` | generative | 7.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `liquid-touch` | interactive-mouse | 7.1 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `sim-slime-mold-growth` | simulation | 7.1 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `flow-sort` | image | 7.1 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `quantum-fractal` | image | 7.1 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `aerogel-smoke` | image | 7.1 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `liquid-smear` | image | 7.1 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen-cybernetic-ferro-coral` | generative | 7.0 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `chromatic-reaction-diffusion` | artistic | 7.0 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-hyper-labyrinth` | generative | 7.0 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `zipper-reveal` | image | 7.0 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `liquid-chrome-ripple` | image | 6.9 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `hybrid-magnetic-field` | generative | 6.9 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `digital-moss` | image | 6.9 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `audio-voronoi-displacement` | distortion | 6.9 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen_fluffy_raincloud` | unknown | 6.9 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `time-lag-map` | image | 6.9 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `hybrid-reaction-diffusion-glass` | simulation | 6.9 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `radiating-haze` | image | 6.8 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gravity-lens` | image | 6.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `impasto-swirl` | image | 6.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `light-leaks` | image | 6.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `holographic-contour` | artistic | 6.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `holographic-projection` | visual-effects | 6.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `hybrid-sdf-plasma` | generative | 6.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `ink_dispersion_alpha` | liquid-effects | 6.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `liquid-prism-cascade` | artistic | 6.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `liquid-swirl` | distortion | 6.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `hybrid-chromatic-liquid` | distortion | 6.8 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `kimi_nebula_depth` | unknown | 6.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. MISSING JSON. |
| `particle-disperse` | image | 6.8 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `sim-decay-system` | artistic | 6.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen_julia_set` | unknown | 6.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. MISSING JSON. |
| `stellar-plasma` | generative | 6.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-singularity-forge` | generative | 6.7 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen_rainbow_smoke` | unknown | 6.7 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `perspective-tilt` | image | 6.7 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `nano-repair` | image | 6.7 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-prismatic-aether-loom` | generative | 6.7 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `slime-drip` | image | 6.7 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `liquid-prism` | distortion | 6.7 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `sim-ink-diffusion` | artistic | 6.7 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `liquid_magnetic_ferro` | liquid-effects | 6.6 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `data-stream-corruption` | image | 6.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `charcoal-rub` | image | 6.6 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `underwater_caustics` | lighting-effects | 6.6 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `poly-art` | image | 6.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `vortex-prism` | image | 6.5 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `liquid_crystal_birefringence` | distortion | 6.5 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `split-flap-display` | image | 6.5 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `sim-sand-dunes` | simulation | 6.5 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `rgb-split-glitch` | image | 6.5 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen-neural-bioluminescence-matrix` | generative | 6.5 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `encaustic-wax` | image | 6.5 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `liquid-mirror` | image | 6.4 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `crumpled-paper` | image | 6.4 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gravity-well` | distortion | 6.4 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `physarum` | simulation | 6.4 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `pixel-wind-chimes` | image | 6.4 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen-stellar-plasma-ouroboros` | generative | 6.4 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `particle-swarm` | image | 6.4 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `raindrop-ripples` | image | 6.4 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `bio_lenia_continuous` | simulation | 6.4 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `aurora_borealis` | generative | 6.4 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `warp_drive` | unknown | 6.3 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `nano-assembler` | simulation | 6.3 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `vortex-distortion` | distortion | 6.3 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `ascii-decode` | interactive-mouse | 6.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `cosmic-jellyfish` | generative | 6.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `bubble-lens` | image | 6.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `infinite-fractal-feedback` | image | 6.2 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen-abyssal-chrono-coral` | generative | 6.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `rgb-fluid` | image | 6.2 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `cmyk-halftone-interactive` | image | 6.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `rain` | image | 6.2 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen-hyper-refractive-rain-matrix` | generative | 6.2 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `sim-smoke-trails` | simulation | 6.2 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `hybrid-voronoi-glass` | distortion | 6.2 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `chromatic-focus-interactive` | visual-effects | 6.2 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `biomimetic-scales` | image | 6.1 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `rgb-ripple-waves` | image | 6.1 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `rgb-topology` | visual-effects | 6.1 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `graphic_novel` | unknown | 6.1 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. MISSING JSON. |
| `retro_phosphor_dream` | retro-glitch | 6.1 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `vortex-drag` | image | 6.0 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `fabric-zipper` | image | 6.0 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `chromatic-swirl` | distortion | 6.0 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `pin-art-3d` | image | 6.0 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `glass-shatter` | image | 6.0 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `hyper-space-jump` | image | 5.9 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `rgb-shift-brush` | image | 5.9 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `infinite-spiral-zoom` | image | 5.9 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `cyber-physical-portal` | image | 5.9 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `ink-bleed` | image | 5.9 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `rgb-iso-lines` | image | 5.9 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `cross-stitch` | image | 5.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `kintsugi-repair` | image | 5.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-bioluminescent-aether-pulsar` | generative | 5.8 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `crystal-refraction` | image | 5.8 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `ink-marbling` | image | 5.8 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `rgb-distance-split` | visual-effects | 5.8 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `flip-matrix` | image | 5.7 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `infinite-zoom-lens` | image | 5.7 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen-magnetic-ferrofluid` | generative | 5.7 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `rgb-ripple-distortion` | image | 5.7 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `glitch-cathedral` | image | 5.7 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `interactive-pcb-traces` | image | 5.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `temporal-echo` | image | 5.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `glitch-reveal` | image | 5.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `sim-heat-haze-field` | distortion | 5.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `frosted-glass-lens` | image | 5.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-quantum-aether-origami` | generative | 5.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `interactive-film-burn` | image | 5.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `engraving-stipple` | artistic | 5.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `rgb-delay-brush` | image | 5.6 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `glitch-ripple-drag` | image | 5.6 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen-fractal-clockwork` | generative | 5.6 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `vortex-warp` | image | 5.5 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `viscous-drag` | liquid-effects | 5.5 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `dynamic-lens-flares` | image | 5.5 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `cyber-slit-scan` | interactive-mouse | 5.5 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `strip-scan-glitch` | image | 5.5 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `generative-psy-swirls` | generative | 5.5 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen_hyper_warp` | unknown | 5.4 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `datamosh-brush` | image | 5.4 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `stipple-engraving` | image | 5.4 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `rotoscope-ink` | artistic | 5.4 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `interactive-halftone-spin` | image | 5.4 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `digital-haze` | image | 5.4 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `sliding-tile-glitch` | image | 5.4 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen-chromodynamic-plasma-collider` | generative | 5.4 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `rain-ripples` | image | 5.4 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `retro-gameboy` | image | 5.3 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `kimi_fractal_dreams` | unknown | 5.3 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `parallax-shift` | distortion | 5.3 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `luminescent-glass-tiles` | distortion | 5.3 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen_kimi_nebula` | unknown | 5.3 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `sequin-flip` | image | 5.3 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `neon-contour-drag` | image | 5.3 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `edge-glow-mouse` | image | 5.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `venetian-blinds` | image | 5.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `cyber-hex-armor` | image | 5.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `glass-bead-curtain` | image | 5.2 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen-crystalline-chrono-dyson` | generative | 5.2 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `ascii-shockwave` | image | 5.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `chromatic-shockwave` | image | 5.2 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `paper-burn` | interactive-mouse | 5.2 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `magma-fissure` | image | 5.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `voronoi-chaos` | distortion | 5.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `cyber-rain-interactive` | retro-glitch | 5.2 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `knitted-fabric` | image | 5.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `glass-brick-distortion` | image | 5.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-graviton-plasma-lotus` | generative | 5.2 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `voronoi-faceted-glass` | image | 5.1 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `kaleido-portal-interactive` | interactive-mouse | 5.1 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `kimi_quantum_field` | unknown | 5.1 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `slinky-distort` | image | 5.1 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `neon-edge-reveal` | image | 5.1 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `generative-turing-veins` | generative | 5.1 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `aero-chromatics` | simulation | 5.1 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `block-distort-interactive` | interactive-mouse | 5.1 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `cyber-magnifier` | interactive-mouse | 5.1 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `glass-wall` | image | 5.1 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-nebular-chrono-astrolabe` | generative | 5.0 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `cyber-lens` | image | 5.0 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `glass-wipes` | image | 5.0 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `circuit-breaker` | interactive-mouse | 5.0 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `rorschach-inkblot` | image | 5.0 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `prismatic-3d-compositor` | image | 5.0 KB | B | complex | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `voronoi-zoom-turbulence` | image | 5.0 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `sphere-projection` | image | 5.0 KB | B | complex | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `hyper-tensor-fluid` | advanced-hybrid | — | B | hybrids | pending | — | none | New creation: tensor_flow, navier_stokes, depth_aware |
| `neural-raymarcher` | advanced-hybrid | — | B | hybrids | pending | — | none | New creation: sdf_raymarching, neural_pattern, volumetric |
| `chromatic-rd-cascade` | advanced-hybrid | — | B | hybrids | pending | — | none | New creation: reaction_diffusion, chromatic_aberration, feedback |
| `gravitational-lensing` | advanced-hybrid | — | B | hybrids | pending | — | none | New creation: physics_simulation, spacetime_distortion, raytracing |
| `cellular-automata-3d` | advanced-hybrid | — | B | hybrids | pending | — | none | New creation: cellular_automata, 3d_texture, raymarching |
| `spectral-flow-hybrid` | advanced-hybrid | — | B | hybrids | pending | — | none | New creation: pixel_sorting, optical_flow, spectral_analysis |
| `multi-fractal-compositor` | advanced-hybrid | — | B | hybrids | pending | — | none | New creation: mandelbrot, julia, lyapunov, hybrid_fractals |
| `mouse-voronoi-displacement` | advanced-hybrid | — | B | hybrids | pending | — | none | New creation: voronoi, mouse_displacement, displacement_mapping |
| `fractal-boids-field` | advanced-hybrid | — | B | hybrids | pending | — | none | New creation: boids_flocking, fractal_noise, vector_field |
| `holographic-interferometry` | advanced-hybrid | — | B | hybrids | pending | — | none | New creation: interference_patterns, holography, depth_parallax |
| `liquid-viscous-simple` | image | 4.9 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `atmos_volumetric_fog` | lighting-effects | 4.9 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `fractal-kaleidoscope` | image | 4.8 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `lenia` | simulation | 4.8 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `video-echo-chamber` | image | 4.8 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `gen-feedback-echo-chamber` | image | 4.8 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `reaction-diffusion` | simulation | 4.7 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `sine-wave` | image | 4.6 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `holographic-prism` | image | 4.6 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `digital-decay` | image | 4.5 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `neon-pulse` | image | 4.5 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `infinite-video-feedback` | image | 4.5 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `gen_grok4_perlin` | unknown | 4.4 KB | B | mouse_interactive | pending | — | none | Add mouse from scratch. MISSING JSON. |
| `neon-edge-radar` | interactive-mouse | 4.4 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `sim-fluid-feedback-field-pass3` | unknown | 4.3 KB | B | mouse_interactive | pending | — | none | Add mouse from scratch. MISSING JSON. |
| `holographic-glitch` | image | 4.3 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `holographic_interference` | lighting-effects | 4.2 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `hybrid-fractal-feedback` | generative | 4.0 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `prismatic-feedback-loop` | image | 4.0 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `holographic-edge-ripple` | image | 4.0 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `fire_smoke_volumetric` | simulation | 4.0 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `sim-fluid-feedback-field-pass1` | unknown | 3.9 KB | B | mouse_interactive | pending | — | none | Add mouse from scratch. MISSING JSON. |
| `neon-warp` | image | 3.9 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `neon-echo` | image | 3.9 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `optical-feedback` | image | 3.9 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `neon-topology` | visual-effects | 3.9 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `holographic-shatter` | image | 3.9 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `holographic-sticker` | visual-effects | 3.8 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `temporal_echo` | distortion | 3.8 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `liquid-metal` | image | 3.7 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `neon-pulse-stream` | image | 3.7 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `holographic-projection-failure` | retro-glitch | 3.6 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `neon-ripple-split` | interactive-mouse | 3.5 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `halftone` | image | 3.5 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `heat-haze-gpt52` | image | 3.5 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `luma-flow-field` | simulation | 3.5 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `neon-strings` | image | 3.4 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `phantom-lag` | image | 3.3 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `scanline-sorting` | image | 3.3 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `scan-distort-gpt52` | image | 3.2 KB | B | mouse_interactive | pending | — | none | Add mouse interaction. Current: none. |
| `kinetic_tiles` | unknown | 5.0 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. MISSING JSON. |
| `hex-circuit` | visual-effects | 5.0 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `cyber-organic` | image | 5.0 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `cosmic-web` | generative | 5.0 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `refractive-bubbles` | image | 5.0 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `foil-impression` | image | 5.0 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `gen-cymatic-plasma-mandalas` | generative | 4.9 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `lichtenberg-fractal` | generative | 4.9 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `spectral-mesh` | image | 4.9 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `neon-contour-interactive` | artistic | 4.9 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `molten-glass` | image | 4.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `glass-brick-wall` | distortion | 4.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `quantum-superposition` | image | 4.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `gen-superfluid-quantum-foam` | generative | 4.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `ascii-lens` | image | 4.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `gen-celestial-glass-tornado` | generative | 4.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `x-ray-reveal` | image | 4.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `spectral-vortex` | image | 4.8 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `divine-light` | image | 4.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `gen-silica-tsunami` | generative | 4.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `interactive-voronoi-web` | image | 4.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `refraction-shards` | image | 4.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `solarize-warp` | image | 4.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `triangle-mosaic` | image | 4.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `breathing-kaleidoscope` | image | 4.7 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `color-blindness` | image | 4.7 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `voxel-depth-sort` | image | 4.7 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `rain-lens-wipe` | image | 4.7 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `bubble-chamber` | generative | 4.7 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `lens-flare-brush` | image | 4.7 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `predator-camouflage` | distortion | 4.7 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `temporal-rift` | image | 4.7 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `quantum-flux` | interactive-mouse | 4.7 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-neuro-kinetic-bloom` | generative | 4.7 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `interactive-glitch-cubes` | image | 4.7 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `phosphor-magnifier` | image | 4.7 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `voronoi-light` | image | 4.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `ascii-flow` | retro-glitch | 4.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `neon-edge-diffusion` | image | 4.6 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `pixel-storm` | image | 4.6 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `pixel-rain` | image | 4.6 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `neon-pulse-edge` | image | 4.6 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `magnetic-luma-sort` | image | 4.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `frost-reveal` | image | 4.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `voronoi-glass` | image | 4.6 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `bayer-dither-interactive` | retro-glitch | 4.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `adaptive-mosaic` | geometric | 4.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-lenia-2` | generative | 4.5 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `ambient-liquid` | image | 4.5 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `voronoi-shatter` | image | 4.5 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `neon-light` | image | 4.5 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `flux-core` | image | 4.5 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `iso-hills` | artistic | 4.5 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `bubble-wrap` | image | 4.5 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `interactive-ripple` | image | 4.4 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `magnetic-rgb` | image | 4.4 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `energy-shield` | interactive-mouse | 4.4 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `neon-fluid-warp` | image | 4.4 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `radial-hex-lens` | image | 4.4 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `cyber-trace` | interactive-mouse | 4.4 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `rainbow-vector-field` | image | 4.4 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `vinyl-scratch` | image | 4.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `crt-phosphor-decay` | retro-glitch | 4.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `chroma-lens` | image | 4.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `signal-modulation` | image | 4.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `tilt-shift` | image | 4.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `cyber-focus` | image | 4.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `spectral-glitch-sort` | retro-glitch | 4.3 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `neon-poly-grid` | geometric | 4.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `ferrofluid` | image | 4.3 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `black-hole` | image | 4.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `fluid-grid` | image | 4.3 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `psychedelic-noise-flow` | interactive-mouse | 4.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `digital-reveal` | image | 4.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `dimension-slicer` | distortion | 4.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `plastic-bricks` | image | 4.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `interactive-kuwahara` | image | 4.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `data-slicer` | image | 4.2 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `optical-illusion-spin` | image | 4.2 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `motion-heatmap` | image | 4.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `mouse-gravity` | image | 4.2 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `chroma-threads` | image | 4.2 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `luma-glass` | distortion | 4.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `cyber-glitch-hologram` | image | 4.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `digital-compression` | image | 4.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `electric-contours` | image | 4.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `reality-tear` | interactive-mouse | 4.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `chronos-brush` | image | 4.2 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `vhs-jog` | image | 4.2 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen_cyclic_automaton` | unknown | 4.2 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `interactive-glitch` | image | 4.2 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `luma-refraction` | image | 4.2 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `neon-flashlight` | image | 4.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `origami-fold` | image | 4.1 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `luma-velocity-melt` | image | 4.1 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `gen_reaction_diffusion` | unknown | 4.1 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `sim-fluid-feedback-field-pass2` | unknown | 4.1 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `luma-smear-interactive` | image | 4.1 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `ascii-glyph` | image | 4.1 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `night-vision-scope` | image | 4.1 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `cyber-rain` | image | 4.1 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `quantum-prism` | image | 4.1 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `luma-topography` | image | 4.1 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `hex-lens` | image | 4.1 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `liquid-lens` | image | 4.1 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `gen-ethereal-quantum-medusa` | generative | 4.1 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen-kinetic-neo-brutalist-megastructure` | generative | 4.1 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `ring_slicer` | unknown | 4.1 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. MISSING JSON. |
| `kimi_chromatic_warp` | unknown | 4.0 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `hex-pulse` | image | 4.0 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click-triggered effects. |
| `magnetic-chroma` | image | 4.0 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `interactive-origami` | image | 4.0 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `refraction-tunnel` | image | 4.0 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `matrix-curtain` | image | 4.0 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `luma-force` | image | 4.0 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `cyber-grid-pulse` | visual-effects | 4.0 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `cyber-scan` | visual-effects | 4.0 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `paper-cutout` | image | 4.0 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `reactive-glass-grid` | image | 4.0 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `liquid-warp-interactive` | distortion | 4.0 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `magnetic-ring` | image | 4.0 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `elastic-surface` | image | 4.0 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `pixel-sort-explorer` | image | 4.0 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `pixel-reveal` | image | 4.0 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `mirror-dimension` | artistic | 3.9 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `interactive-voronoi-lens` | image | 3.9 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `complex-exponent-warp` | distortion | 3.9 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `motion-revealer` | interactive-mouse | 3.9 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `fractal-noise-dissolve` | image | 3.9 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `codebreaker-reveal` | interactive-mouse | 3.9 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `neural-nexus` | image | 3.9 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `directional-blur-wipe` | image | 3.9 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `pixel-explode` | interactive-mouse | 3.9 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `blueprint-reveal` | image | 3.9 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen_capabilities` | unknown | 3.9 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `contour-flow` | image | 3.9 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `interactive-emboss` | image | 3.9 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gamma-ray-burst` | image | 3.9 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `hypnotic-spiral` | image | 3.9 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `kaleido-scope` | geometric | 3.9 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `halftone-reveal` | image | 3.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `spirograph-reveal` | image | 3.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `navier-stokes-dye` | simulation | 3.8 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `spectral-smear` | image | 3.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `data-moshing` | image | 3.8 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `split-dimension` | image | 3.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `temporal-distortion-field` | distortion | 3.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `chroma-vortex` | visual-effects | 3.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `moire-interference` | image | 3.8 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `interactive-pixel-wind` | image | 3.7 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `ripple-blocks` | image | 3.7 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `fiber-optic-weave` | image | 3.7 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `scanline-drift` | retro-glitch | 3.7 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `speed-lines-focus` | image | 3.7 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `cyber-halftone-scanner` | image | 3.7 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `circular-pixelate` | image | 3.7 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `fractal-glass-distort` | distortion | 3.7 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `data-stream` | image | 3.7 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `bio-touch` | image | 3.6 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `heat-haze` | image | 3.6 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `prism-displacement` | distortion | 3.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `steampunk-gear-lens` | image | 3.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `radial-slit-scan` | image | 3.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `gen_wave_equation` | unknown | 3.6 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `spectral-rain` | image | 3.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `scan-slice` | image | 3.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `magnetic-pixels` | image | 3.6 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `cursor-aura` | image | 3.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `stipple-render` | artistic | 3.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `alucinate` | image | 3.6 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `luminance-wind` | image | 3.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `interactive-zoom-blur` | image | 3.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `quantum-tunnel-interactive` | image | 3.6 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `sonar-pulse` | image | 3.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `frosty-window` | image | 3.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `spectral-distortion` | image | 3.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `laser-burn` | image | 3.6 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `quantum-cursor` | interactive-mouse | 3.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `interactive-rgb-split` | image | 3.6 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `magnetic-edge` | interactive-mouse | 3.6 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `thermal-vision` | image | 3.5 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `pixel-focus` | image | 3.5 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `focal-pixelate` | interactive-mouse | 3.5 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `kimi_spotlight` | unknown | 3.5 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `ion-stream` | image | 3.5 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `chroma-kinetic` | image | 3.5 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `mouse-pixel-sort` | image | 3.5 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `vhs-tracking-mouse` | image | 3.5 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `interactive-glitch-brush` | image | 3.5 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `crt-clear-zone` | image | 3.5 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `spectral-slit-scan` | image | 3.5 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `dynamic-halftone` | image | 3.5 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `hex-mosaic` | image | 3.5 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `wave-halftone` | image | 3.5 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `polka-wave` | image | 3.5 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `kimi_ripple_touch` | unknown | 3.5 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. MISSING JSON. |
| `velvet-vortex` | image | 3.5 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `luma-magnetism` | interactive-mouse | 3.5 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `melting-oil` | simulation | 3.5 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `luma-slice-interactive` | image | 3.4 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `fractal-image-surf` | image | 3.4 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `glitch-slice-mirror` | image | 3.4 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `pixel-sort-radial` | image | 3.4 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `quad-mirror` | image | 3.4 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `pixel-stretch-interactive` | image | 3.4 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `volumetric-god-rays` | image | 3.4 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `kinetic-dispersion` | interactive-mouse | 3.4 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `spectral-waves` | image | 3.4 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `virtual-lens` | image | 3.4 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `chroma-depth-tunnel` | image | 3.4 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `luma-melt-interactive` | liquid-effects | 3.4 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `pixel-drag-smear` | image | 3.4 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `elastic-strip` | image | 3.4 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `quantum-field-visualizer` | visual-effects | 3.4 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `cyber-lattice` | image | 3.4 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `voronoi` | geometric | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `xerox-degrade` | image | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `vertical-slice-wave` | interactive-mouse | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `data-scanner` | visual-effects | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `thermal-touch` | image | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `quantized-ripples` | image | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `cyber-ripples` | image | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `stereoscopic-3d` | interactive-mouse | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `directional-glitch` | image | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `divine-light-gpt52` | image | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `neon-cursor-trace` | image | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `pixel-scattering` | image | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `polka-dot-reveal` | image | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `voxel-grid` | visual-effects | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `magnetic-interference` | image | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `spectral-brush` | image | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `oscilloscope-overlay` | image | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `kaleido-scope-grokcf1` | geometric | 3.3 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `quantum-ripples` | image | 3.3 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `scanline-wave` | interactive-mouse | 3.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `echo-ripple` | image | 3.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `polar-warp-interactive` | image | 3.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `tesseract-fold` | image | 3.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `page-curl-interactive` | image | 3.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `pixelate-blast` | retro-glitch | 3.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `tile-twist` | image | 3.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `spiral-lens` | image | 3.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `double-exposure` | image | 3.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `mosaic-reveal` | image | 3.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `chromatic-mosaic-projector` | image | 3.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `chrono-slit-scan` | image | 3.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `digital-lens` | image | 3.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `crt-magnet` | image | 3.2 KB | B | mouse_interactive | pending | — | basic | Enhance mouse: add click states, physics, spring following. |
| `pixel-depth-sort` | image | 3.1 KB | B | mouse_interactive | pending | — | basic | Add mouse interaction. Current: basic. |
| `phosphor-decay` | visual-effects | 3.1 KB | B | mouse_interactive | pending | — | basic | Add mouse interaction. Current: basic. |
| `pixel-sand` | image | 3.1 KB | B | mouse_interactive | pending | — | basic | Add mouse interaction. Current: basic. |
| `luma-pixel-sort` | artistic | 3.1 KB | B | mouse_interactive | pending | — | basic | Add mouse interaction. Current: basic. |
| `interactive-magnetic-ripple` | image | 3.1 KB | B | mouse_interactive | pending | — | basic | Add mouse interaction. Current: basic. |
| `data-slicer-interactive` | interactive-mouse | 3.1 KB | B | mouse_interactive | pending | — | basic | Add mouse interaction. Current: basic. |
| `pixel-stretch-cross` | image | 3.1 KB | B | mouse_interactive | pending | — | basic | Add mouse interaction. Current: basic. |
| `hyper-chromatic-delay` | image | 3.1 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `sonic-boom` | distortion | 3.1 KB | B | mouse_interactive | pending | — | basic | Add mouse interaction. Current: basic. |
| `mirror-drag` | interactive-mouse | 3.1 KB | B | mouse_interactive | pending | — | advanced | Optimize: performance, alpha modes, randomization safety, JSON cleanup. |
| `signal-tuner` | image | 3.1 KB | B | mouse_interactive | pending | — | basic | Add mouse interaction. Current: basic. |
| `waveform-glitch` | image | 3.0 KB | B | mouse_interactive | pending | — | basic | Add mouse interaction. Current: basic. |
| `temporal-rgb-smear` | image | 3.0 KB | B | mouse_interactive | pending | — | basic | Add mouse interaction. Current: basic. |
| `elastic-chromatic` | image | 3.0 KB | B | mouse_interactive | pending | — | basic | Add mouse interaction. Current: basic. |
| `bitonic-sort` | image | 3.0 KB | B | mouse_interactive | pending | — | basic | Add mouse interaction. Current: basic. |

---

## Maintenance Instructions

### Status Values
- `pending` — Not started
- `in-progress` — Currently being worked on
- `completed` — Done and verified
- `skipped` — Intentionally deferred
- `deferred` — Postponed to later phase

### How to Update
1. After completing a shader, change its Status from `pending` to `completed`
2. After creating a new shader, append it to the appropriate Phase section
3. Re-run `scripts/scan_shaders.py` after any WGSL changes to refresh mouse detection
4. Update this file in-place — do not create duplicates
