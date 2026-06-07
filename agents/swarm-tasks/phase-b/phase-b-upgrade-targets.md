# Phase B Upgrade Targets

**Generated:** 2026-04-18  
**Phase:** B  
**Total Target Entries:** 125  
**Unique Shaders Targeted:** 101  
**Shaders in Multiple Categories:** 20

---

## Executive Summary

This document lists ranked upgrade targets for the Pixelocity shader library Phase B campaign. Four upgrade tracks are targeted:

| Upgrade Track | Count | Focus |
|---------------|-------|-------|
| **Mouse Response** | 35 | Add `mouse-driven` interactivity to image-input shaders in distortion, artistic, liquid-effects, visual-effects, lighting-effects, image, and post-processing categories. |
| **Multi-Pass** | 30 | Decompose large monolithic shaders (>8 KB) that have not yet been split into multi-pass pipelines. |
| **Advanced Alpha** | 30 | Introduce sophisticated alpha compositing to shaders with glow, light, volumetric, feedback, temporal, or distortion characteristics. |
| **Audio Reactive** | 30 | Add `audio-reactive` features to shaders with rhythmic, pulsing, or temporal potential that are not yet audio-aware. |

### Global Exclusions
The following already-refactored multi-pass shaders are **excluded from all categories**:
- `quantum-foam` (and `pass1` / `pass2` / `pass3`)
- `aurora-rift` (and `pass1` / `pass2`)
- `aurora-rift-2` (and `pass1` / `pass2`)
- `sim-fluid-feedback-field` (and `pass1` / `pass2` / `pass3`)

In addition, `_hash_library.wgsl` and all `_template_*.wgsl` files are excluded.

---

## 1. Mouse-Response Targets

| Priority | Shader ID | Category | Size (bytes) | Rationale / Notes |
|----------|-----------|----------|--------------|-------------------|
| 1 | ✅ `glass_refraction_alpha` | distortion | 8,733 | Non-generative distortion shader without mouse-driven interactivity; size 8733 bytes; also targeted for advanced alpha |
| 2 | ✅ `gravitational-lensing` | distortion | 8,327 | Non-generative distortion shader without mouse-driven interactivity; size 8327 bytes |
| 3 | ✅ `hybrid-spectral-sorting` | distortion | 7,690 | Non-generative distortion shader without mouse-driven interactivity; size 7690 bytes |
| 4 | ✅ `spectral-flow-sorting` | distortion | 7,655 | Non-generative distortion shader without mouse-driven interactivity; size 7655 bytes |
| 5 | ✅ `audio-voronoi-displacement` | distortion | 7,057 | Non-generative distortion shader without mouse-driven interactivity; size 7057 bytes |
| 6 | ✅ `hybrid-chromatic-liquid` | distortion | 6,993 | Non-generative distortion shader without mouse-driven interactivity; size 6993 bytes; already audio-reactive — skip audio pass; also targeted for advanced alpha |
| 7 | ✅ `liquid_crystal_birefringence` | distortion | 6,648 | Non-generative distortion shader without mouse-driven interactivity; size 6648 bytes |
| 8 | ✅ `hybrid-voronoi-glass` | distortion | 6,303 | Non-generative distortion shader without mouse-driven interactivity; size 6303 bytes |
| 9 | `sim-heat-haze-field` | distortion | 5,768 | Non-generative distortion shader without mouse-driven interactivity; size 5768 bytes |
| 10 | `temporal_echo` | distortion | 3,922 | Non-generative distortion shader without mouse-driven interactivity; size 3922 bytes; already audio-reactive — skip audio pass; also targeted for advanced alpha |
| 11 | `artistic_painterly_oil` | artistic | 9,401 | Non-generative artistic shader without mouse-driven interactivity; size 9401 bytes |
| 12 | `chromatic-reaction-diffusion` | artistic | 7,186 | Non-generative artistic shader without mouse-driven interactivity; size 7186 bytes |
| 13 | `sim-decay-system` | artistic | 6,986 | Non-generative artistic shader without mouse-driven interactivity; size 6986 bytes |
| 14 | `sim-ink-diffusion` | artistic | 6,822 | Non-generative artistic shader without mouse-driven interactivity; size 6822 bytes |
| 15 | `ink_dispersion_alpha` | liquid-effects | 6,993 | Non-generative liquid-effects shader without mouse-driven interactivity; size 6993 bytes |
| 16 | `parallax_depth_layers` | visual-effects | 9,865 | Non-generative visual-effects shader without mouse-driven interactivity; size 9865 bytes |
| 17 | `gen-velocity-bloom` | lighting-effects | 7,068 | Non-generative lighting-effects shader without mouse-driven interactivity; size 7068 bytes; also targeted for advanced alpha |
| 18 | `underwater_caustics` | lighting-effects | 6,738 | Non-generative lighting-effects shader without mouse-driven interactivity; size 6738 bytes; also targeted for advanced alpha |
| 19 | `sim-volumetric-fake` | lighting-effects | 5,859 | Non-generative lighting-effects shader without mouse-driven interactivity; size 5859 bytes; also targeted for advanced alpha |
| 20 | `atmos_volumetric_fog` | lighting-effects | 5,025 | Non-generative lighting-effects shader without mouse-driven interactivity; size 5025 bytes; also targeted for advanced alpha |
| 21 | `holographic_interference` | lighting-effects | 4,273 | Non-generative lighting-effects shader without mouse-driven interactivity; size 4273 bytes |
| 22 | `parallax-glow-compositor` | image | 9,865 | Non-generative image shader without mouse-driven interactivity; size 9865 bytes; also targeted for advanced alpha |
| 23 | `liquid-v1` | image | 9,698 | Non-generative image shader without mouse-driven interactivity; size 9698 bytes |
| 24 | `gemstone-fractures` | image | 7,543 | Non-generative image shader without mouse-driven interactivity; size 7543 bytes; also targeted for advanced alpha |
| 25 | `gen-temporal-motion-smear` | image | 6,689 | Non-generative image shader without mouse-driven interactivity; size 6689 bytes; also targeted for advanced alpha |
| 26 | `liquid-viscous-grokcf1` | image | 6,677 | Non-generative image shader without mouse-driven interactivity; size 6677 bytes |
| 27 | `digital-waves` | image | 6,018 | Non-generative image shader without mouse-driven interactivity; size 6018 bytes |
| 28 | `rain-ripples` | image | 5,479 | Non-generative image shader without mouse-driven interactivity; size 5479 bytes |
| 29 | `fractal-kaleidoscope` | image | 4,962 | Non-generative image shader without mouse-driven interactivity; size 4962 bytes |
| 30 | `gen-feedback-echo-chamber` | image | 4,869 | Non-generative image shader without mouse-driven interactivity; size 4869 bytes; also targeted for advanced alpha |
| 31 | `cyber-halftone-scanner` | image | 3,758 | Non-generative image shader without mouse-driven interactivity; size 3758 bytes |
| 32 | `alucinate` | image | 3,674 | Non-generative image shader without mouse-driven interactivity; size 3674 bytes |
| 33 | `kaleidoscope` | image | 3,460 | Non-generative image shader without mouse-driven interactivity; size 3460 bytes |
| 34 | `xerox-degrade` | image | 3,425 | Non-generative image shader without mouse-driven interactivity; size 3425 bytes |
| 35 | `phantom-lag` | image | 3,412 | Non-generative image shader without mouse-driven interactivity; size 3412 bytes |

## 2. Multi-Pass Targets

| Priority | Shader ID | Category | Size (bytes) | Rationale / Notes |
|----------|-----------|----------|--------------|-------------------|
| 1 | ✅ `liquid-optimized` | liquid-effects | 22,466 | Large monolithic shader (22466 bytes) not yet multi-pass; good candidate for decomposition; also targeted for audio-reactive |
| 2 | ✅ `spectrogram-displace` | image | 21,828 | Large monolithic shader (21828 bytes) not yet multi-pass; good candidate for decomposition |
| 3 | ✅ `digital-glitch` | image | 20,712 | Large monolithic shader (20712 bytes) not yet multi-pass; good candidate for decomposition |
| 4 | ✅ `liquid` | image | 18,928 | Large monolithic shader (18928 bytes) not yet multi-pass; good candidate for decomposition |
| 5 | `rgb-glitch-displacement` | retro-glitch | 18,507 | Large monolithic shader (18507 bytes) not yet multi-pass; good candidate for decomposition; also targeted for audio-reactive |
| 6 | ✅ `vortex` | image | 18,015 | Large monolithic shader (18015 bytes) not yet multi-pass; good candidate for decomposition |
| 7 | `gen-quantum-superposition` | generative | 17,911 | Large monolithic shader (17911 bytes) not yet multi-pass; good candidate for decomposition |
| 8 | `recursion-mirror-vortex` | artistic | 16,968 | Large monolithic shader (16968 bytes) not yet multi-pass; good candidate for decomposition |
| 9 | `chromatic-phase-inversion` | artistic | 16,926 | Large monolithic shader (16926 bytes) not yet multi-pass; good candidate for decomposition; also targeted for audio-reactive; also targeted for advanced alpha |
| 10 | `spectral-bleed-confinement` | artistic | 16,910 | Large monolithic shader (16910 bytes) not yet multi-pass; good candidate for decomposition; also targeted for audio-reactive; also targeted for advanced alpha |
| 11 | `tensor-flow-sculpting` | image | 16,512 | Large monolithic shader (16512 bytes) not yet multi-pass; good candidate for decomposition |
| 12 | `gen-gravitational-strain` | generative | 16,338 | Large monolithic shader (16338 bytes) not yet multi-pass; good candidate for decomposition |
| 13 | `gen-inverse-mandelbrot` | generative | 16,275 | Large monolithic shader (16275 bytes) not yet multi-pass; good candidate for decomposition |
| 14 | `gen-hyperbolic-tessellation` | generative | 16,186 | Large monolithic shader (16186 bytes) not yet multi-pass; good candidate for decomposition |
| 15 | `gen-chromatic-metamorphosis` | generative | 15,772 | Large monolithic shader (15772 bytes) not yet multi-pass; good candidate for decomposition |
| 16 | `chromatic-crawler` | image | 15,391 | Large monolithic shader (15391 bytes) not yet multi-pass; good candidate for decomposition |
| 17 | `neural-resonance` | image | 14,900 | Large monolithic shader (14900 bytes) not yet multi-pass; good candidate for decomposition |
| 18 | `quantum-smear` | image | 14,754 | Large monolithic shader (14754 bytes) not yet multi-pass; good candidate for decomposition |
| 19 | `rainbow-cloud` | image | 14,547 | Large monolithic shader (14547 bytes) not yet multi-pass; good candidate for decomposition |
| 20 | `gen-holographic-data-core` | generative | 14,476 | Large monolithic shader (14476 bytes) not yet multi-pass; good candidate for decomposition |
| 21 | `gen-chronos-labyrinth` | generative | 14,430 | Large monolithic shader (14430 bytes) not yet multi-pass; good candidate for decomposition |
| 22 | `chromatic-folds` | image | 14,268 | Large monolithic shader (14268 bytes) not yet multi-pass; good candidate for decomposition |
| 23 | `crt-tv` | retro-glitch | 14,080 | Large monolithic shader (14080 bytes) not yet multi-pass; good candidate for decomposition; also targeted for audio-reactive |
| 24 | `vhs-tracking` | image | 13,823 | Large monolithic shader (13823 bytes) not yet multi-pass; good candidate for decomposition |
| 25 | `gen-art-deco-sky` | generative | 13,722 | Large monolithic shader (13722 bytes) not yet multi-pass; good candidate for decomposition |
| 26 | `pixel-sort-glitch` | distortion | 13,671 | Large monolithic shader (13671 bytes) not yet multi-pass; good candidate for decomposition; also targeted for audio-reactive |
| 27 | `chromatic-folds-2` | image | 13,491 | Large monolithic shader (13491 bytes) not yet multi-pass; good candidate for decomposition |
| 28 | `stella-orbit` | image | 13,475 | Large monolithic shader (13475 bytes) not yet multi-pass; good candidate for decomposition |
| 29 | `scan-distort` | image | 13,228 | Large monolithic shader (13228 bytes) not yet multi-pass; good candidate for decomposition |
| 30 | `infinite-zoom` | image | 13,189 | Large monolithic shader (13189 bytes) not yet multi-pass; good candidate for decomposition |

## 3. Advanced Alpha Targets

| Priority | Shader ID | Category | Size (bytes) | Rationale / Notes |
|----------|-----------|----------|--------------|-------------------|
| 1 | ✅ `spectral-bleed-confinement` | artistic | 16,910 | artistic shader with glow/light/distortion characteristics; alpha compositing would enhance blending; also targeted for audio-reactive; also targeted for multipass |
| 2 | ✅ `photonic-caustics` | image | 10,204 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending; also targeted for audio-reactive |
| 3 | ✅ `crystal-refraction` | image | 5,906 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending |
| 4 | ✅ `gen-feedback-echo-chamber` | image | 4,869 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending; also targeted for mouse-response |
| 5 | ✅ `neon-edge-pulse` | visual-effects | 9,865 | visual-effects shader with glow/light/distortion characteristics; alpha compositing would enhance blending |
| 6 | ✅ `glass_refraction_alpha` | distortion | 8,733 | distortion shader with glow/light/distortion characteristics; alpha compositing would enhance blending; also targeted for mouse-response |
| 7 | ✅ `volumetric-depth-zoom` | image | 8,224 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending |
| 8 | ✅ `crystal-facets` | distortion | 7,964 | distortion shader with glow/light/distortion characteristics; alpha compositing would enhance blending; also targeted for audio-reactive |
| 9 | `cosmic-flow` | image | 7,797 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending |
| 10 | `gen-velocity-bloom` | lighting-effects | 7,068 | lighting-effects shader with glow/light/distortion characteristics; alpha compositing would enhance blending; also targeted for mouse-response |
| 11 | `gen-temporal-motion-smear` | image | 6,689 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending; also targeted for mouse-response |
| 12 | `green-tracer` | image | 6,538 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending |
| 13 | `sim-volumetric-fake` | lighting-effects | 5,859 | lighting-effects shader with glow/light/distortion characteristics; alpha compositing would enhance blending; also targeted for mouse-response |
| 14 | `atmos_volumetric_fog` | lighting-effects | 5,025 | lighting-effects shader with glow/light/distortion characteristics; alpha compositing would enhance blending; also targeted for mouse-response |
| 15 | `prismatic-feedback-loop` | image | 4,092 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending; also targeted for audio-reactive |
| 16 | `neon-warp` | image | 4,034 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending |
| 17 | `temporal_echo` | distortion | 3,922 | distortion shader with glow/light/distortion characteristics; alpha compositing would enhance blending; also targeted for audio-reactive; also targeted for mouse-response |
| 18 | `chromatic-phase-inversion` | artistic | 16,926 | artistic shader with glow/light/distortion characteristics; alpha compositing would enhance blending; also targeted for audio-reactive; also targeted for multipass |
| 19 | `astral-veins` | image | 10,589 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending |
| 20 | `bioluminescent` | image | 9,950 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending |
| 21 | `parallax-glow-compositor` | image | 9,865 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending; also targeted for mouse-response |
| 22 | `wave-equation` | image | 8,374 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending |
| 23 | `volumetric-rainbow-clouds` | image | 8,245 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending |
| 24 | `gemstone-fractures` | image | 7,543 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending; also targeted for mouse-response |
| 25 | `aerogel-smoke` | image | 7,247 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending |
| 26 | `lidar` | image | 7,193 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending |
| 27 | `hybrid-chromatic-liquid` | distortion | 6,993 | distortion shader with glow/light/distortion characteristics; alpha compositing would enhance blending; also targeted for audio-reactive; also targeted for mouse-response |
| 28 | `underwater_caustics` | lighting-effects | 6,738 | lighting-effects shader with glow/light/distortion characteristics; alpha compositing would enhance blending; also targeted for mouse-response |
| 29 | `pp-chromatic` | post-processing | 5,378 | post-processing shader with glow/light/distortion characteristics; alpha compositing would enhance blending |
| 30 | `neon-contour-drag` | image | 5,377 | image shader with glow/light/distortion characteristics; alpha compositing would enhance blending |

## 4. Audio-Reactive Targets

| Priority | Shader ID | Category | Size (bytes) | Rationale / Notes |
|----------|-----------|----------|--------------|-------------------|
| 1 | `rgb-glitch-displacement` | retro-glitch | 18,507 | retro-glitch shader with rhythmic/pulsing potential; not yet audio-reactive; also targeted for multipass |
| 2 | `temporal_echo` | distortion | 3,922 | distortion shader with rhythmic/pulsing potential; not yet audio-reactive; also targeted for advanced alpha; also targeted for mouse-response |
| 3 | `chromatic-phase-inversion` | artistic | 16,926 | artistic shader with rhythmic/pulsing potential; not yet audio-reactive; also targeted for multipass; also targeted for advanced alpha |
| 4 | `hybrid-magnetic-field` | generative | 7,098 | generative shader with rhythmic/pulsing potential; not yet audio-reactive |
| 5 | `hybrid-chromatic-liquid` | distortion | 6,993 | distortion shader with rhythmic/pulsing potential; not yet audio-reactive; also targeted for advanced alpha; also targeted for mouse-response |
| 6 | `liquid-prism` | distortion | 6,835 | distortion shader with rhythmic/pulsing potential; not yet audio-reactive |
| 7 | `liquid-optimized` | liquid-effects | 22,466 | liquid-effects shader with rhythmic/pulsing potential; not yet audio-reactive; also targeted for multipass |
| 8 | ✅ `spectral-bleed-confinement` | artistic | 16,910 | artistic shader with rhythmic/pulsing potential; not yet audio-reactive; also targeted for multipass; also targeted for advanced alpha |
| 9 | `volumetric-cloud-nebula` | generative | 8,284 | generative shader with rhythmic/pulsing potential; not yet audio-reactive |
| 10 | `hybrid-particle-fluid` | simulation | 7,346 | simulation shader with rhythmic/pulsing potential; not yet audio-reactive |
| 11 | `hybrid-sdf-plasma` | generative | 6,993 | generative shader with rhythmic/pulsing potential; not yet audio-reactive |
| 12 | `aurora_borealis` | generative | 6,509 | generative shader with rhythmic/pulsing potential; not yet audio-reactive |
| 13 | `hybrid-noise-kaleidoscope` | generative | 6,252 | generative shader with rhythmic/pulsing potential; not yet audio-reactive |
| 14 | `hex-circuit` | visual-effects | 5,096 | visual-effects shader with rhythmic/pulsing potential; not yet audio-reactive |
| 15 | `spectral-glitch-sort` | retro-glitch | 4,428 | retro-glitch shader with rhythmic/pulsing potential; not yet audio-reactive |
| 16 | `prismatic-feedback-loop` | image | 4,092 | image shader with rhythmic/pulsing potential; not yet audio-reactive; also targeted for advanced alpha |
| 17 | `quantum-field-visualizer` | visual-effects | 3,438 | visual-effects shader with rhythmic/pulsing potential; not yet audio-reactive |
| 18 | `gen-grokcf-voronoi` | generative | 0 | generative shader with rhythmic/pulsing potential; not yet audio-reactive |
| 19 | `gen-grid` | generative | 0 | generative shader with rhythmic/pulsing potential; not yet audio-reactive |
| 20 | `liquid-displacement` | liquid-effects | 17,361 | liquid-effects shader with rhythmic/pulsing potential; not yet audio-reactive |
| 21 | `scanline-tear` | retro-glitch | 15,523 | retro-glitch shader with rhythmic/pulsing potential; not yet audio-reactive |
| 22 | `crt-tv` | retro-glitch | 14,080 | retro-glitch shader with rhythmic/pulsing potential; not yet audio-reactive; also targeted for multipass |
| 23 | `pixel-sort-glitch` | distortion | 13,671 | distortion shader with rhythmic/pulsing potential; not yet audio-reactive; also targeted for multipass |
| 24 | ✅ `photonic-caustics` | image | 10,204 | image shader with rhythmic/pulsing potential; not yet audio-reactive; also targeted for advanced alpha |
| 25 | ✅ `crystal-facets` | distortion | 7,964 | distortion shader with rhythmic/pulsing potential; not yet audio-reactive; also targeted for advanced alpha |
| 26 | `physarum-grokcf1` | simulation | 7,694 | simulation shader with rhythmic/pulsing potential; not yet audio-reactive |
| 27 | `physarum-gemini` | simulation | 7,662 | simulation shader with rhythmic/pulsing potential; not yet audio-reactive |
| 28 | `hybrid-reaction-diffusion-glass` | simulation | 7,034 | simulation shader with rhythmic/pulsing potential; not yet audio-reactive |
| 29 | `liquid-prism-cascade` | artistic | 6,993 | artistic shader with rhythmic/pulsing potential; not yet audio-reactive |
| 30 | `hybrid-cyber-organic` | generative | 6,981 | generative shader with rhythmic/pulsing potential; not yet audio-reactive |

---

## Methodology

1. **JSON definitions** from `shader_definitions/*/*.json` were parsed to extract IDs, categories, features, tags, and descriptions.
2. **WGSL file sizes** from `public/shaders/*.wgsl` were cross-referenced.
3. **Scoring heuristics** ranked each shader against the four upgrade tracks:
   - *Mouse-response*: non-generative shaders without `mouse-driven` in priority categories.
   - *Multi-pass*: shaders >8 KB that are not already split into passes.
   - *Advanced alpha*: shaders with glow, light, volumetric, feedback, temporal, or distortion metadata.
   - *Audio-reactive*: shaders with temporal, animated, rhythmic, or pulsing characteristics not already tagged `audio-reactive` or `audio-driven`.
4. Already-refactored multi-pass shaders and template files were excluded globally.
5. Final lists were capped to keep the total near ~120 entries while preserving high-value targets.

