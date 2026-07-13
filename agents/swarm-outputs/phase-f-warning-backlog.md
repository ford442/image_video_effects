# Phase F Warning Backlog Report

**Generated:** 2026-06-29T04:13:24.898262  
**Agent:** Agent 4f — Warning Backlog Analyst  

## Executive Summary

- **Total shaders audited:** 1,260
- **Shaders passing:** 949
- **Shaders with warnings:** 311
- **Critical issues:** 0 ✅
- **NAGA failures:** 0
- **Total warning instances:** 344

All CRITICAL issues have been resolved. Remaining work is strictly WARNING-level cleanup.

## Top Warning Categories

| Category | Instances | Unique Shaders | Example Issue |
|----------|-----------|----------------|---------------|
| ALPHA | 223 | 223 | ALPHA: Hardcoded alpha=1.0 in non-generative shader |
| JSON | 120 | 120 | JSON: No JSON definition found |
| WORKGROUP | 1 | 1 | WORKGROUP: Workgroup size [16, 16, 4] = 1024 > 256 baseline |

## Category Recommendations

### ALPHA: Hardcoded alpha=1.0 in non-generative shaders

- **Instances:** 223 across 223 shaders
- **Impact:** Non-generative shaders that hardcode alpha prevent blend/opacity controls from working correctly.
- **Fix pattern:** Replace `alpha = 1.0` with a bind-group opacity/alpha uniform, or derive alpha from input texture/params.
- **Priority categories (most affected):**
  - `interactive-mouse`: 45
  - `artistic`: 38
  - `unknown`: 31
  - `advanced-hybrid`: 21
  - `image`: 20
  - `simulation`: 19
  - `retro-glitch`: 10
  - `distortion`: 9
  - `post-processing`: 8
  - `geometric`: 6

### JSON: Missing JSON definition

- **Instances:** 120 across 120 shaders
- **Impact:** Shaders without JSON definitions are not discoverable by the app catalog and cannot be loaded by users.
- **Fix pattern:** Create `shader_definitions/<category>/<shader-id>.json` with title, description, category, uniforms, and parameters.
- **Affected categories (detected):**
  - `unknown`: 89
  - `generative`: 22
  - `interactive-mouse`: 3
  - `image`: 2
  - `artistic`: 1
  - `liquid-effects`: 1
  - `geometric`: 1
  - `visual-effects`: 1

### Other Categories

- **WORKGROUP** (1 instances, 1 shaders): WORKGROUP: Workgroup size [16, 16, 4] = 1024 > 256 baseline

## Ranked Backlog: Shaders to Fix Next

Sorted by issue count (descending), then shader size (descending) as a proxy for complexity/impact.

| Rank | Shader ID | Issues | Size (bytes) | JSON Category | JSON Exists | Issue Categories |
|------|-----------|--------|--------------|---------------|-------------|------------------|
| 1 | `tensor-flow-sculpt` | 2 | 17,667 | unknown | no | ALPHA, JSON |
| 2 | `spectral-bleed-confine` | 2 | 16,307 | unknown | no | ALPHA, JSON |
| 3 | `cyber-organic-ecosystem` | 2 | 9,030 | unknown | no | ALPHA, JSON |
| 4 | `frost-reveal-crystal` | 2 | 8,979 | unknown | no | ALPHA, JSON |
| 5 | `liquid-smear-structure` | 2 | 8,898 | unknown | no | ALPHA, JSON |
| 6 | `ethereal-swirl-coupled` | 2 | 8,747 | unknown | no | ALPHA, JSON |
| 7 | `cyber-trace-structure` | 2 | 8,672 | unknown | no | ALPHA, JSON |
| 8 | `chromatic-folds-bilateral` | 2 | 8,611 | unknown | no | ALPHA, JSON |
| 9 | `liquid-oil-iridescence` | 2 | 8,308 | unknown | no | ALPHA, JSON |
| 10 | `kimi_ripple_touch` | 2 | 7,950 | interactive-mouse | yes | ALPHA, JSON |
| 11 | `viscous-drag-bilateral` | 2 | 7,946 | unknown | no | ALPHA, JSON |
| 12 | `chromatic-focus-guided` | 2 | 7,942 | unknown | no | ALPHA, JSON |
| 13 | `chromatic-crawler-structure` | 2 | 7,845 | unknown | no | ALPHA, JSON |
| 14 | `distortion-gravitational-prismatic` | 2 | 7,837 | unknown | no | ALPHA, JSON |
| 15 | `data-stream-corruption-hdr` | 2 | 7,588 | unknown | no | ALPHA, JSON |
| 16 | `fluid-grid-rgba-fluid` | 2 | 7,508 | unknown | no | ALPHA, JSON |
| 17 | `dynamic-lens-flares-prismatic` | 2 | 7,286 | unknown | no | ALPHA, JSON |
| 18 | `cyber-lattice-bilateral` | 2 | 7,026 | unknown | no | ALPHA, JSON |
| 19 | `fractal-glass-distort-bilateral` | 2 | 6,700 | unknown | no | ALPHA, JSON |
| 20 | `energy-shield-blackbody` | 2 | 6,553 | unknown | no | ALPHA, JSON |
| 21 | `data-stream-structure` | 2 | 6,467 | unknown | no | ALPHA, JSON |
| 22 | `ferrofluid-em` | 2 | 6,305 | unknown | no | ALPHA, JSON |
| 23 | `chroma-threads-gabor` | 2 | 6,205 | unknown | no | ALPHA, JSON |
| 24 | `gamma-ray-burst-blackbody` | 2 | 6,107 | unknown | no | ALPHA, JSON |
| 25 | `digital-reveal-guided` | 2 | 6,096 | unknown | no | ALPHA, JSON |
| 26 | `elastic-chromatic-explosion` | 2 | 6,079 | unknown | no | ALPHA, JSON |
| 27 | `chroma-lens-iridescence` | 2 | 6,063 | unknown | no | ALPHA, JSON |
| 28 | `data-scanner-gabor` | 2 | 5,868 | unknown | no | ALPHA, JSON |
| 29 | `digital-lens-prismatic` | 2 | 5,725 | unknown | no | ALPHA, JSON |
| 30 | `kinetic_tiles` | 2 | 5,430 | geometric | yes | ALPHA, JSON |
| 31 | `chroma-depth-tunnel-prismatic` | 2 | 5,113 | unknown | no | ALPHA, JSON |
| 32 | `sim-fluid-feedback-field-pass1` | 2 | 4,897 | unknown | no | ALPHA, JSON |
| 33 | `sim-fluid-feedback-field-pass2` | 2 | 4,416 | unknown | no | ALPHA, JSON |
| 34 | `chromatic-phase-inversion` | 1 | 17,317 | artistic | yes | ALPHA |
| 35 | `tensor-flow-sculpting` | 1 | 17,299 | image | yes | ALPHA |
| 36 | `recursion-mirror-vortex` | 1 | 17,148 | artistic | yes | ALPHA |
| 37 | `liquid-displacement` | 1 | 16,921 | liquid-effects | yes | ALPHA |
| 38 | `quantum-smear` | 1 | 14,827 | artistic | yes | ALPHA |
| 39 | `gen-bioluminescent-abyss` | 1 | 14,687 | unknown | no | JSON |
| 40 | `chromatic-folds` | 1 | 14,385 | artistic | yes | ALPHA |
| 41 | `crt-tv` | 1 | 14,080 | retro-glitch | yes | ALPHA |
| 42 | `chromatic-folds-2` | 1 | 13,566 | artistic | yes | ALPHA |
| 43 | `stella-orbit` | 1 | 13,563 | artistic | yes | ALPHA |
| 44 | `photonic-caustics-iridescence` | 1 | 13,277 | advanced-hybrid | yes | ALPHA |
| 45 | `aurora-rift-pass2` | 1 | 13,052 | lighting-effects | yes | ALPHA |
| 46 | `aurora-rift-2-pass2` | 1 | 12,871 | lighting-effects | yes | ALPHA |
| 47 | `gen-alien-flora-ecosystem` | 1 | 12,405 | unknown | no | JSON |
| 48 | `quantum-foam-pass2` | 1 | 12,331 | simulation | yes | ALPHA |
| 49 | `gen_trails` | 1 | 12,051 | generative | yes | JSON |
| 50 | `gen-art-deco-sky-prismatic` | 1 | 11,854 | unknown | no | JSON |
| 51 | `ethereal-swirl` | 1 | 11,576 | distortion | yes | ALPHA |
| 52 | `pyramid-bandprocess-pass2` | 1 | 11,558 | image | yes | ALPHA |
| 53 | `pyramid-composite-pass3` | 1 | 11,548 | image | yes | ALPHA |
| 54 | `gen_grok4_perlin` | 1 | 11,492 | generative | yes | JSON |
| 55 | `photonic-caustics` | 1 | 11,209 | simulation | yes | ALPHA |
| 56 | `tensor-flow-morphological` | 1 | 11,029 | advanced-hybrid | yes | ALPHA |
| 57 | `lichtenberg-fractal` | 1 | 10,960 | simulation | yes | ALPHA |
| 58 | `alpha-multi-state-ecosystem` | 1 | 10,942 | simulation | yes | ALPHA |
| 59 | `deep-workgroup-multi-effect-blend` | 1 | 10,777 | advanced-hybrid | yes | WORKGROUP |
| 60 | `astral-veins` | 1 | 10,761 | artistic | yes | ALPHA |
| 61 | `glass_refraction_alpha` | 1 | 10,597 | artistic | yes | ALPHA |
| 62 | `gen-bismuth-citadel-crystal` | 1 | 10,589 | unknown | no | JSON |
| 63 | `chromatic-infection` | 1 | 10,583 | artistic | yes | ALPHA |
| 64 | `lenia-on-video` | 1 | 10,553 | simulation | yes | ALPHA |
| 65 | `fabric-step` | 1 | 10,551 | artistic | yes | ALPHA |
| 66 | `neural-dreamscape` | 1 | 10,542 | artistic | yes | ALPHA |
| 67 | `gen_fluffy_raincloud` | 1 | 10,395 | generative | yes | JSON |
| 68 | `aurora-rift-gemini` | 1 | 10,379 | artistic | yes | ALPHA |
| 69 | `liquid-magnetic-ferro-em` | 1 | 10,351 | advanced-hybrid | yes | ALPHA |
| 70 | `predator-prey` | 1 | 10,325 | simulation | yes | ALPHA |
| 71 | `gen_rainbow_smoke` | 1 | 10,220 | generative | yes | JSON |
| 72 | `sim-slime-mold-growth-em` | 1 | 10,181 | simulation | yes | ALPHA |
| 73 | `gen_grid` | 1 | 10,147 | generative | yes | JSON |
| 74 | `gen_orb` | 1 | 10,062 | generative | yes | JSON |
| 75 | `gen_grok41_plasma` | 1 | 9,996 | generative | yes | JSON |
| 76 | `byte-mosh-explosion` | 1 | 9,995 | advanced-hybrid | yes | ALPHA |
| 77 | `bioluminescent` | 1 | 9,950 | artistic | yes | ALPHA |
| 78 | `audio-reactive-temporal-decay` | 1 | 9,890 | post-processing | yes | ALPHA |
| 79 | `liquid-jelly-fluid` | 1 | 9,724 | unknown | no | JSON |
| 80 | `cosmic-web-structure` | 1 | 9,705 | unknown | no | JSON |
| 81 | `gen_grokcf_voronoi` | 1 | 9,689 | generative | yes | JSON |
| 82 | `liquid-metal` | 1 | 9,630 | liquid-effects | yes | ALPHA |
| 83 | `gen-string-theory-structure` | 1 | 9,615 | unknown | no | JSON |
| 84 | `gen-abyssal-leviathan-iridescence` | 1 | 9,613 | unknown | no | JSON |
| 85 | `dla-crystals` | 1 | 9,595 | artistic | yes | ALPHA |
| 86 | `gen_grokcf_interference` | 1 | 9,537 | generative | yes | JSON |
| 87 | `cosmic-jellyfish-coupled` | 1 | 9,527 | unknown | no | JSON |
| 88 | `liquid-viscous` | 1 | 9,512 | liquid-effects | yes | ALPHA |
| 89 | `kimi-flock-symphony-em` | 1 | 9,485 | unknown | no | JSON |
| 90 | `glass-refraction-prismatic` | 1 | 9,461 | advanced-hybrid | yes | ALPHA |
| 91 | `cmyk-halftone-explosion` | 1 | 9,407 | advanced-hybrid | yes | ALPHA |
| 92 | `iridescent-oil-slick` | 1 | 9,288 | artistic | yes | ALPHA |
| 93 | `gen_grok41_mandelbrot` | 1 | 9,213 | generative | yes | JSON |
| 94 | `fabric-step-gabor` | 1 | 9,146 | advanced-hybrid | yes | ALPHA |
| 95 | `alpha-reaction-diffusion-rgba` | 1 | 9,128 | simulation | yes | ALPHA |
| 96 | `charcoal-rub-diffusion` | 1 | 9,124 | advanced-hybrid | yes | ALPHA |
| 97 | `gen_kimi_crystal` | 1 | 9,060 | generative | yes | JSON |
| 98 | `pyramid-downsample-pass1` | 1 | 9,009 | image | yes | ALPHA |
| 99 | `quantum-wormhole` | 1 | 8,999 | artistic | yes | ALPHA |
| 100 | `astral-kaleidoscope` | 1 | 8,984 | artistic | yes | ALPHA |
| 101 | `pixel-sorter` | 1 | 8,961 | visual-effects | yes | ALPHA |
| 102 | `astral-kaleidoscope-gemini` | 1 | 8,923 | artistic | yes | ALPHA |
| 103 | `astral-kaleidoscope-grokcf1` | 1 | 8,920 | artistic | yes | ALPHA |
| 104 | `poincare-tile` | 1 | 8,896 | artistic | yes | ALPHA |
| 105 | `hyperbolic-dreamweaver-julia` | 1 | 8,895 | unknown | no | JSON |
| 106 | `liquid-warp` | 1 | 8,871 | interactive-mouse | yes | ALPHA |
| 107 | `bubble-lens-coupled` | 1 | 8,811 | advanced-hybrid | yes | ALPHA |
| 108 | `crystal-illuminator-iridescence` | 1 | 8,737 | unknown | no | JSON |
| 109 | `impasto-swirl-bilateral` | 1 | 8,736 | unknown | no | JSON |
| 110 | `gen_grok4_life` | 1 | 8,714 | generative | yes | JSON |
| 111 | `crystal-freeze` | 1 | 8,680 | interactive-mouse | yes | ALPHA |
| 112 | `gravity-well-em` | 1 | 8,627 | unknown | no | JSON |
| 113 | `bismuth-crystal-growth` | 1 | 8,626 | unknown | no | JSON |
| 114 | `cymatic-sand` | 1 | 8,574 | simulation | yes | ALPHA |
| 115 | `gen-singularity-forge-blackbody` | 1 | 8,566 | unknown | no | JSON |
| 116 | `steamy-glass` | 1 | 8,553 | simulation | yes | ALPHA |
| 117 | `astral-kaleidoscope-julia` | 1 | 8,537 | unknown | no | JSON |
| 118 | `liquid-rainbow-prismatic` | 1 | 8,519 | unknown | no | JSON |
| 119 | `liquid-touch` | 1 | 8,494 | interactive-mouse | yes | ALPHA |
| 120 | `aurora-borealis-iridescence` | 1 | 8,463 | advanced-hybrid | yes | ALPHA |
| 121 | `tesseract-fold` | 1 | 8,463 | image | yes | ALPHA |
| 122 | `gen_reaction_diffusion` | 1 | 8,426 | generative | yes | JSON |
| 123 | `multi-turing` | 1 | 8,410 | artistic | yes | ALPHA |
| 124 | `anamorphic-flare-iridescence` | 1 | 8,397 | unknown | no | JSON |
| 125 | `wave-equation` | 1 | 8,374 | simulation | yes | ALPHA |
| 126 | `liquid-perspective` | 1 | 8,370 | liquid-effects | yes | ALPHA |
| 127 | `sim-heat-haze-blackbody` | 1 | 8,218 | advanced-hybrid | yes | ALPHA |
| 128 | `ink-bleed-fluid` | 1 | 8,212 | unknown | no | JSON |
| 129 | `hyper-tensor-fluid` | 1 | 8,200 | advanced-hybrid | yes | ALPHA |
| 130 | `spectral-flow-sorting` | 1 | 8,186 | advanced-hybrid | yes | ALPHA |
| 131 | `magnetic-dipole` | 1 | 8,164 | artistic | yes | ALPHA |
| 132 | `neon-pulse-edge` | 1 | 8,149 | lighting-effects | yes | ALPHA |
| 133 | `gen-neural-fractal-hdr` | 1 | 8,144 | unknown | no | JSON |
| 134 | `quantum-ripples` | 1 | 8,096 | interactive-mouse | yes | ALPHA |
| 135 | `digital-glitch-explosion` | 1 | 8,084 | unknown | no | JSON |
| 136 | `voronoi-dynamics` | 1 | 8,075 | artistic | yes | ALPHA |
| 137 | `gemstone-fractures-crystal` | 1 | 7,997 | unknown | no | JSON |
| 138 | `rgb-ripple-distortion` | 1 | 7,905 | image | yes | ALPHA |
| 139 | `elastic-surface` | 1 | 7,901 | distortion | yes | ALPHA |
| 140 | `pixel-rain` | 1 | 7,899 | retro-glitch | yes | ALPHA |
| 141 | `bioluminescent-blackbody` | 1 | 7,842 | advanced-hybrid | yes | ALPHA |
| 142 | `infinite-fractal-feedback-hdr` | 1 | 7,817 | unknown | no | JSON |
| 143 | `kaleidoscope` | 1 | 7,816 | distortion | yes | ALPHA |
| 144 | `cosmic-flow` | 1 | 7,797 | artistic | yes | ALPHA |
| 145 | `optical-flow-tracer` | 1 | 7,765 | post-processing | yes | ALPHA |
| 146 | `distortion_gravitational_lens` | 1 | 7,709 | artistic | yes | ALPHA |
| 147 | `echo-trace` | 1 | 7,671 | artistic | yes | ALPHA |
| 148 | `hyperbolic-dreamweaver` | 1 | 7,670 | geometric | yes | ALPHA |
| 149 | `glitch-cathedral` | 1 | 7,668 | interactive-mouse | yes | ALPHA |
| 150 | `vhs-tracking` | 1 | 7,660 | retro-glitch | yes | ALPHA |
| 151 | `audio-reactive-pyramid` | 1 | 7,656 | post-processing | yes | ALPHA |
| 152 | `chromatic-folds-gemini` | 1 | 7,610 | artistic | yes | ALPHA |
| 153 | `retro-phosphor-stipple` | 1 | 7,606 | advanced-hybrid | yes | ALPHA |
| 154 | `rgb-split-glitch` | 1 | 7,600 | interactive-mouse | yes | ALPHA |
| 155 | `gen_julia_set` | 1 | 7,579 | generative | yes | JSON |
| 156 | `frosted-glass-lens-iridescence` | 1 | 7,517 | unknown | no | JSON |
| 157 | `oscilloscope-overlay` | 1 | 7,504 | interactive-mouse | yes | ALPHA |
| 158 | `slime-drip` | 1 | 7,497 | image | yes | ALPHA |
| 159 | `snow` | 1 | 7,487 | artistic | yes | ALPHA |
| 160 | `interactive-origami-coupled` | 1 | 7,459 | unknown | no | JSON |
| 161 | `log-polar-droste` | 1 | 7,410 | distortion | yes | ALPHA |
| 162 | `vortex-warp-coupled` | 1 | 7,403 | unknown | no | JSON |
| 163 | `gen_hyper_warp` | 1 | 7,395 | generative | yes | JSON |
| 164 | `vhs-tracking-bilateral` | 1 | 7,339 | advanced-hybrid | yes | ALPHA |
| 165 | `sim-slime-mold-growth` | 1 | 7,311 | simulation | yes | ALPHA |
| 166 | `interactive-magnetic-ripple-em` | 1 | 7,306 | unknown | no | JSON |
| 167 | `chronos-brush-explosion` | 1 | 7,297 | unknown | no | JSON |
| 168 | `crumpled-paper` | 1 | 7,291 | image | yes | ALPHA |
| 169 | `cyber-scan-gabor` | 1 | 7,281 | unknown | no | JSON |
| 170 | `galaxy` | 1 | 7,265 | artistic | yes | JSON |
| 171 | `flow-sort` | 1 | 7,253 | simulation | yes | ALPHA |
| 172 | `quantum-fractal` | 1 | 7,250 | artistic | yes | ALPHA |
| 173 | `digital-moss-rgba` | 1 | 7,245 | unknown | no | JSON |
| 174 | `gen_kimi_nebula` | 1 | 7,231 | generative | yes | JSON |
| 175 | `flip-matrix` | 1 | 7,217 | geometric | yes | ALPHA |
| 176 | `frost-reveal` | 1 | 7,204 | image | yes | ALPHA |
| 177 | `dimension-slicer-guided` | 1 | 7,201 | unknown | no | JSON |
| 178 | `cyber-rain-em` | 1 | 7,199 | unknown | no | JSON |
| 179 | `lidar` | 1 | 7,193 | artistic | yes | ALPHA |
| 180 | `steamy-glass-volumetric` | 1 | 7,188 | unknown | no | JSON |
| 181 | `chromatic-reaction-diffusion` | 1 | 7,186 | advanced-hybrid | yes | ALPHA |
| 182 | `retro-phosphor-hdr` | 1 | 7,178 | advanced-hybrid | yes | ALPHA |
| 183 | `honey-melt-blackbody` | 1 | 7,176 | unknown | no | JSON |
| 184 | `melting-oil-blackbody` | 1 | 7,174 | unknown | no | JSON |
| 185 | `chroma-vortex-coupled` | 1 | 7,161 | unknown | no | JSON |
| 186 | `heat-haze-volumetric` | 1 | 7,133 | unknown | no | JSON |
| 187 | `kimi_fractal_dreams` | 1 | 7,119 | generative | yes | JSON |
| 188 | `radiating-haze` | 1 | 7,110 | artistic | yes | ALPHA |
| 189 | `cursor-aura-explosion` | 1 | 7,106 | unknown | no | JSON |
| 190 | `gen-quasicrystal-iridescence` | 1 | 7,097 | unknown | no | JSON |
| 191 | `split-flap-display` | 1 | 7,062 | simulation | yes | ALPHA |
| 192 | `glass-brick-distortion` | 1 | 7,055 | distortion | yes | ALPHA |
| 193 | `time-lag-map` | 1 | 7,047 | geometric | yes | ALPHA |
| 194 | `gen_cyclic_automaton` | 1 | 7,043 | generative | yes | JSON |
| 195 | `vaporwave-horizon-prismatic` | 1 | 7,038 | unknown | no | JSON |
| 196 | `hybrid-reaction-diffusion-glass` | 1 | 7,034 | hybrid | yes | ALPHA |
| 197 | `vortex-distortion` | 1 | 7,018 | distortion | yes | ALPHA |
| 198 | `interactive-pixel-wind-structure` | 1 | 7,006 | unknown | no | JSON |
| 199 | `kimi_nebula_depth` | 1 | 6,999 | generative | yes | JSON |
| 200 | `fire-smoke-volumetric-fog` | 1 | 6,992 | unknown | no | JSON |
| 201 | `particle-disperse` | 1 | 6,987 | interactive-mouse | yes | ALPHA |
| 202 | `sim-decay-system` | 1 | 6,986 | simulation | yes | ALPHA |
| 203 | `spec-temporal-path-tracer` | 1 | 6,971 | advanced-hybrid | yes | ALPHA |
| 204 | `kimi_quantum_field` | 1 | 6,918 | generative | yes | JSON |
| 205 | `gravity-lens` | 1 | 6,885 | interactive-mouse | yes | ALPHA |
| 206 | `radiating-displacement` | 1 | 6,866 | artistic | yes | ALPHA |
| 207 | `nano-repair` | 1 | 6,863 | interactive-mouse | yes | ALPHA |
| 208 | `temporal-rgb-ghost` | 1 | 6,862 | post-processing | yes | ALPHA |
| 209 | `breathing-kaleidoscope-morph` | 1 | 6,845 | unknown | no | JSON |
| 210 | `audio-reactive-rgb-dispersion` | 1 | 6,826 | post-processing | yes | ALPHA |
| 211 | `temporal_echo` | 1 | 6,820 | lighting-effects | yes | ALPHA |
| 212 | `hyper-chromatic-delay` | 1 | 6,794 | interactive-mouse | yes | ALPHA |
| 213 | `data-stream-corruption` | 1 | 6,785 | interactive-mouse | yes | ALPHA |
| 214 | `gen_wave_equation` | 1 | 6,783 | generative | yes | JSON |
| 215 | `edge-glow-mouse-em` | 1 | 6,772 | unknown | no | JSON |
| 216 | `charcoal-rub` | 1 | 6,738 | interactive-mouse | yes | ALPHA |
| 217 | `underwater_caustics` | 1 | 6,738 | lighting-effects | yes | ALPHA |
| 218 | `spec-runge-kutta-advection` | 1 | 6,674 | simulation | yes | ALPHA |
| 219 | `gen_psychedelic_spiral` | 1 | 6,664 | generative | yes | JSON |
| 220 | `temporal-layered-time-stamps` | 1 | 6,646 | post-processing | yes | ALPHA |
| 221 | `sim-sand-dunes` | 1 | 6,638 | simulation | yes | ALPHA |
| 222 | `green-tracer` | 1 | 6,630 | artistic | yes | ALPHA |
| 223 | `pixel-wind-chimes` | 1 | 6,540 | interactive-mouse | yes | ALPHA |
| 224 | `cyber-ripples-coupled` | 1 | 6,534 | unknown | no | JSON |
| 225 | `particle-swarm` | 1 | 6,534 | interactive-mouse | yes | ALPHA |
| 226 | `digital-decay` | 1 | 6,529 | retro-glitch | yes | ALPHA |
| 227 | `aurora_borealis` | 1 | 6,509 | lighting-effects | yes | ALPHA |
| 228 | `fractal-noise-dissolve-nlm` | 1 | 6,485 | unknown | no | JSON |
| 229 | `divine-light-iridescence` | 1 | 6,482 | unknown | no | JSON |
| 230 | `hyper-space-jump-blackbody` | 1 | 6,441 | unknown | no | JSON |
| 231 | `nano-assembler` | 1 | 6,433 | simulation | yes | ALPHA |
| 232 | `rgb-distance-split` | 1 | 6,417 | visual-effects | yes | ALPHA |
| 233 | `phantom-lag-history` | 1 | 6,384 | unknown | no | JSON |
| 234 | `interactive-origami` | 1 | 6,363 | geometric | yes | ALPHA |
| 235 | `crystalline-shatter` | 1 | 6,362 | image | yes | ALPHA |
| 236 | `navier-stokes-dye` | 1 | 6,339 | artistic | yes | ALPHA |
| 237 | `warp-drive-blackbody` | 1 | 6,332 | unknown | no | JSON |
| 238 | `magnetic-rgb` | 1 | 6,322 | interactive-mouse | yes | ALPHA |
| 239 | `graphic_novel` | 1 | 6,216 | image | yes | JSON |
| 240 | `digital-glitch-pass2` | 1 | 6,198 | retro-glitch | yes | ALPHA |
| 241 | `plasma` | 1 | 6,186 | artistic | yes | ALPHA |
| 242 | `chroma-kinetic-blackbody` | 1 | 6,120 | unknown | no | JSON |
| 243 | `interactive-voronoi-web` | 1 | 6,095 | interactive-mouse | yes | ALPHA |
| 244 | `crt-phosphor-decay` | 1 | 6,076 | retro-glitch | yes | ALPHA |
| 245 | `warp_drive` | 1 | 6,067 | visual-effects | yes | JSON |
| 246 | `digital-waves` | 1 | 6,018 | retro-glitch | yes | ALPHA |
| 247 | `bubble-wrap` | 1 | 5,983 | interactive-mouse | yes | ALPHA |
| 248 | `neon-pulse-dissolve` | 1 | 5,980 | image | yes | ALPHA |
| 249 | `data-stream-spectral` | 1 | 5,885 | unknown | no | JSON |
| 250 | `color-channel-weave` | 1 | 5,854 | image | yes | ALPHA |
| 251 | `thermal-vision-blackbody` | 1 | 5,840 | advanced-hybrid | yes | ALPHA |
| 252 | `adaptive-mosaic` | 1 | 5,820 | geometric | yes | ALPHA |
| 253 | `posterize-neon-edges` | 1 | 5,797 | image | yes | ALPHA |
| 254 | `pixel-tornado` | 1 | 5,792 | image | yes | ALPHA |
| 255 | `refractive-bubbles` | 1 | 5,788 | interactive-mouse | yes | ALPHA |
| 256 | `interactive-rgb-split-explosion` | 1 | 5,785 | unknown | no | JSON |
| 257 | `interactive-pcb-traces` | 1 | 5,777 | visual-effects | yes | ALPHA |
| 258 | `sim-heat-haze-field` | 1 | 5,768 | simulation | yes | ALPHA |
| 259 | `kimi_liquid_glass` | 1 | 5,722 | liquid-effects | yes | JSON |
| 260 | `spec-blue-noise-stipple` | 1 | 5,655 | artistic | yes | ALPHA |
| 261 | `lorenz-attractor-flow` | 1 | 5,631 | unknown | no | JSON |
| 262 | `scanline-cyberpunk` | 1 | 5,610 | image | yes | ALPHA |
| 263 | `heat-haze-mirage` | 1 | 5,599 | image | yes | ALPHA |
| 264 | `long-exposure` | 1 | 5,587 | post-processing | yes | ALPHA |
| 265 | `brush-strokes` | 1 | 5,572 | unknown | no | JSON |
| 266 | `pixelate-blast` | 1 | 5,528 | unknown | no | JSON |
| 267 | `watercolor-bloom` | 1 | 5,526 | image | yes | ALPHA |
| 268 | `interactive-halftone-spin` | 1 | 5,507 | interactive-mouse | yes | ALPHA |
| 269 | `cmyk-halftone-interactive` | 1 | 5,500 | interactive-mouse | yes | ALPHA |
| 270 | `molten-glass` | 1 | 5,497 | interactive-mouse | yes | ALPHA |
| 271 | `vertical-slice-wave` | 1 | 5,412 | interactive-mouse | yes | ALPHA |
| 272 | `sequin-flip` | 1 | 5,385 | interactive-mouse | yes | ALPHA |
| 273 | `spectrum-bleed` | 1 | 5,375 | retro-glitch | yes | ALPHA |
| 274 | `cyber-rain-interactive` | 1 | 5,374 | retro-glitch | yes | ALPHA |
| 275 | `venetian-blinds` | 1 | 5,355 | interactive-mouse | yes | ALPHA |
| 276 | `cyber-hex-armor` | 1 | 5,352 | interactive-mouse | yes | ALPHA |
| 277 | `ascii-shockwave` | 1 | 5,338 | visual-effects | yes | ALPHA |
| 278 | `oil-slick-iridescence` | 1 | 5,329 | image | yes | ALPHA |
| 279 | `paper-burn` | 1 | 5,319 | interactive-mouse | yes | ALPHA |
| 280 | `magma-fissure` | 1 | 5,315 | interactive-mouse | yes | ALPHA |
| 281 | `voronoi-chaos` | 1 | 5,300 | distortion | yes | ALPHA |
| 282 | `ferrofluid` | 1 | 5,261 | interactive-mouse | yes | ALPHA |
| 283 | `kimi_chromatic_warp` | 1 | 5,227 | interactive-mouse | yes | JSON |
| 284 | `prismatic-3d-compositor` | 1 | 5,142 | interactive-mouse | yes | ALPHA |
| 285 | `sphere-projection` | 1 | 5,129 | interactive-mouse | yes | ALPHA |
| 286 | `thermal-touch-blackbody` | 1 | 5,017 | advanced-hybrid | yes | ALPHA |
| 287 | `liquid-optimized-pass2` | 1 | 4,977 | liquid-effects | yes | ALPHA |
| 288 | `cyber-magnifier` | 1 | 4,966 | interactive-mouse | yes | ALPHA |
| 289 | `fractal-kaleidoscope` | 1 | 4,962 | distortion | yes | ALPHA |
| 290 | `sim-fluid-feedback-field-pass3` | 1 | 4,957 | unknown | no | JSON |
| 291 | `quantum-superposition` | 1 | 4,935 | interactive-mouse | yes | ALPHA |
| 292 | `cross-conv-mouse-bilateral` | 1 | 4,920 | image | yes | ALPHA |
| 293 | `luma-refraction` | 1 | 4,876 | image | yes | ALPHA |
| 294 | `rain-lens-wipe` | 1 | 4,851 | interactive-mouse | yes | ALPHA |
| 295 | `pixel-explode` | 1 | 4,834 | interactive-mouse | yes | ALPHA |
| 296 | `reaction-diffusion` | 1 | 4,830 | artistic | yes | ALPHA |
| 297 | `cursor-aura` | 1 | 4,774 | interactive-mouse | yes | ALPHA |
| 298 | `pixel-storm` | 1 | 4,757 | distortion | yes | ALPHA |
| 299 | `digital-reveal` | 1 | 4,756 | interactive-mouse | yes | ALPHA |
| 300 | `tone-histogram-apply` | 1 | 4,693 | post-processing | yes | ALPHA |
| 301 | `voronoi-glass` | 1 | 4,674 | interactive-mouse | yes | ALPHA |
| 302 | `radial-hex-lens` | 1 | 4,464 | interactive-mouse | yes | ALPHA |
| 303 | `cyber-trace` | 1 | 4,459 | interactive-mouse | yes | ALPHA |
| 304 | `moire-interference` | 1 | 4,459 | interactive-mouse | yes | ALPHA |
| 305 | `rainbow-vector-field` | 1 | 4,457 | interactive-mouse | yes | ALPHA |
| 306 | `kimi_spotlight` | 1 | 4,453 | interactive-mouse | yes | JSON |
| 307 | `speed-lines-focus` | 1 | 4,450 | artistic | yes | ALPHA |
| 308 | `chroma-lens` | 1 | 4,441 | interactive-mouse | yes | ALPHA |
| 309 | `cyber-focus` | 1 | 4,429 | interactive-mouse | yes | ALPHA |
| 310 | `scanline-drift` | 1 | 4,425 | retro-glitch | yes | ALPHA |
| 311 | `ring_slicer` | 1 | 3,574 | image | yes | JSON |

## Appendix: Full Warning Shader List by Category

### ALPHA

- `tensor-flow-sculpt` (17,667 bytes, json_category=unknown, json_exists=no)
- `chromatic-phase-inversion` (17,317 bytes, json_category=artistic, json_exists=yes)
- `tensor-flow-sculpting` (17,299 bytes, json_category=image, json_exists=yes)
- `recursion-mirror-vortex` (17,148 bytes, json_category=artistic, json_exists=yes)
- `liquid-displacement` (16,921 bytes, json_category=liquid-effects, json_exists=yes)
- `spectral-bleed-confine` (16,307 bytes, json_category=unknown, json_exists=no)
- `quantum-smear` (14,827 bytes, json_category=artistic, json_exists=yes)
- `chromatic-folds` (14,385 bytes, json_category=artistic, json_exists=yes)
- `crt-tv` (14,080 bytes, json_category=retro-glitch, json_exists=yes)
- `chromatic-folds-2` (13,566 bytes, json_category=artistic, json_exists=yes)
- `stella-orbit` (13,563 bytes, json_category=artistic, json_exists=yes)
- `photonic-caustics-iridescence` (13,277 bytes, json_category=advanced-hybrid, json_exists=yes)
- `aurora-rift-pass2` (13,052 bytes, json_category=lighting-effects, json_exists=yes)
- `aurora-rift-2-pass2` (12,871 bytes, json_category=lighting-effects, json_exists=yes)
- `quantum-foam-pass2` (12,331 bytes, json_category=simulation, json_exists=yes)
- `ethereal-swirl` (11,576 bytes, json_category=distortion, json_exists=yes)
- `pyramid-bandprocess-pass2` (11,558 bytes, json_category=image, json_exists=yes)
- `pyramid-composite-pass3` (11,548 bytes, json_category=image, json_exists=yes)
- `photonic-caustics` (11,209 bytes, json_category=simulation, json_exists=yes)
- `tensor-flow-morphological` (11,029 bytes, json_category=advanced-hybrid, json_exists=yes)
- `lichtenberg-fractal` (10,960 bytes, json_category=simulation, json_exists=yes)
- `alpha-multi-state-ecosystem` (10,942 bytes, json_category=simulation, json_exists=yes)
- `astral-veins` (10,761 bytes, json_category=artistic, json_exists=yes)
- `glass_refraction_alpha` (10,597 bytes, json_category=artistic, json_exists=yes)
- `chromatic-infection` (10,583 bytes, json_category=artistic, json_exists=yes)
- `lenia-on-video` (10,553 bytes, json_category=simulation, json_exists=yes)
- `fabric-step` (10,551 bytes, json_category=artistic, json_exists=yes)
- `neural-dreamscape` (10,542 bytes, json_category=artistic, json_exists=yes)
- `aurora-rift-gemini` (10,379 bytes, json_category=artistic, json_exists=yes)
- `liquid-magnetic-ferro-em` (10,351 bytes, json_category=advanced-hybrid, json_exists=yes)
- `predator-prey` (10,325 bytes, json_category=simulation, json_exists=yes)
- `sim-slime-mold-growth-em` (10,181 bytes, json_category=simulation, json_exists=yes)
- `byte-mosh-explosion` (9,995 bytes, json_category=advanced-hybrid, json_exists=yes)
- `bioluminescent` (9,950 bytes, json_category=artistic, json_exists=yes)
- `audio-reactive-temporal-decay` (9,890 bytes, json_category=post-processing, json_exists=yes)
- `liquid-metal` (9,630 bytes, json_category=liquid-effects, json_exists=yes)
- `dla-crystals` (9,595 bytes, json_category=artistic, json_exists=yes)
- `liquid-viscous` (9,512 bytes, json_category=liquid-effects, json_exists=yes)
- `glass-refraction-prismatic` (9,461 bytes, json_category=advanced-hybrid, json_exists=yes)
- `cmyk-halftone-explosion` (9,407 bytes, json_category=advanced-hybrid, json_exists=yes)
- `iridescent-oil-slick` (9,288 bytes, json_category=artistic, json_exists=yes)
- `fabric-step-gabor` (9,146 bytes, json_category=advanced-hybrid, json_exists=yes)
- `alpha-reaction-diffusion-rgba` (9,128 bytes, json_category=simulation, json_exists=yes)
- `charcoal-rub-diffusion` (9,124 bytes, json_category=advanced-hybrid, json_exists=yes)
- `cyber-organic-ecosystem` (9,030 bytes, json_category=unknown, json_exists=no)
- `pyramid-downsample-pass1` (9,009 bytes, json_category=image, json_exists=yes)
- `quantum-wormhole` (8,999 bytes, json_category=artistic, json_exists=yes)
- `astral-kaleidoscope` (8,984 bytes, json_category=artistic, json_exists=yes)
- `frost-reveal-crystal` (8,979 bytes, json_category=unknown, json_exists=no)
- `pixel-sorter` (8,961 bytes, json_category=visual-effects, json_exists=yes)
- `astral-kaleidoscope-gemini` (8,923 bytes, json_category=artistic, json_exists=yes)
- `astral-kaleidoscope-grokcf1` (8,920 bytes, json_category=artistic, json_exists=yes)
- `liquid-smear-structure` (8,898 bytes, json_category=unknown, json_exists=no)
- `poincare-tile` (8,896 bytes, json_category=artistic, json_exists=yes)
- `liquid-warp` (8,871 bytes, json_category=interactive-mouse, json_exists=yes)
- `bubble-lens-coupled` (8,811 bytes, json_category=advanced-hybrid, json_exists=yes)
- `ethereal-swirl-coupled` (8,747 bytes, json_category=unknown, json_exists=no)
- `crystal-freeze` (8,680 bytes, json_category=interactive-mouse, json_exists=yes)
- `cyber-trace-structure` (8,672 bytes, json_category=unknown, json_exists=no)
- `chromatic-folds-bilateral` (8,611 bytes, json_category=unknown, json_exists=no)
- `cymatic-sand` (8,574 bytes, json_category=simulation, json_exists=yes)
- `steamy-glass` (8,553 bytes, json_category=simulation, json_exists=yes)
- `liquid-touch` (8,494 bytes, json_category=interactive-mouse, json_exists=yes)
- `aurora-borealis-iridescence` (8,463 bytes, json_category=advanced-hybrid, json_exists=yes)
- `tesseract-fold` (8,463 bytes, json_category=image, json_exists=yes)
- `multi-turing` (8,410 bytes, json_category=artistic, json_exists=yes)
- `wave-equation` (8,374 bytes, json_category=simulation, json_exists=yes)
- `liquid-perspective` (8,370 bytes, json_category=liquid-effects, json_exists=yes)
- `liquid-oil-iridescence` (8,308 bytes, json_category=unknown, json_exists=no)
- `sim-heat-haze-blackbody` (8,218 bytes, json_category=advanced-hybrid, json_exists=yes)
- `hyper-tensor-fluid` (8,200 bytes, json_category=advanced-hybrid, json_exists=yes)
- `spectral-flow-sorting` (8,186 bytes, json_category=advanced-hybrid, json_exists=yes)
- `magnetic-dipole` (8,164 bytes, json_category=artistic, json_exists=yes)
- `neon-pulse-edge` (8,149 bytes, json_category=lighting-effects, json_exists=yes)
- `quantum-ripples` (8,096 bytes, json_category=interactive-mouse, json_exists=yes)
- `voronoi-dynamics` (8,075 bytes, json_category=artistic, json_exists=yes)
- `kimi_ripple_touch` (7,950 bytes, json_category=interactive-mouse, json_exists=yes)
- `viscous-drag-bilateral` (7,946 bytes, json_category=unknown, json_exists=no)
- `chromatic-focus-guided` (7,942 bytes, json_category=unknown, json_exists=no)
- `rgb-ripple-distortion` (7,905 bytes, json_category=image, json_exists=yes)
- `elastic-surface` (7,901 bytes, json_category=distortion, json_exists=yes)
- `pixel-rain` (7,899 bytes, json_category=retro-glitch, json_exists=yes)
- `chromatic-crawler-structure` (7,845 bytes, json_category=unknown, json_exists=no)
- `bioluminescent-blackbody` (7,842 bytes, json_category=advanced-hybrid, json_exists=yes)
- `distortion-gravitational-prismatic` (7,837 bytes, json_category=unknown, json_exists=no)
- `kaleidoscope` (7,816 bytes, json_category=distortion, json_exists=yes)
- `cosmic-flow` (7,797 bytes, json_category=artistic, json_exists=yes)
- `optical-flow-tracer` (7,765 bytes, json_category=post-processing, json_exists=yes)
- `distortion_gravitational_lens` (7,709 bytes, json_category=artistic, json_exists=yes)
- `echo-trace` (7,671 bytes, json_category=artistic, json_exists=yes)
- `hyperbolic-dreamweaver` (7,670 bytes, json_category=geometric, json_exists=yes)
- `glitch-cathedral` (7,668 bytes, json_category=interactive-mouse, json_exists=yes)
- `vhs-tracking` (7,660 bytes, json_category=retro-glitch, json_exists=yes)
- `audio-reactive-pyramid` (7,656 bytes, json_category=post-processing, json_exists=yes)
- `chromatic-folds-gemini` (7,610 bytes, json_category=artistic, json_exists=yes)
- `retro-phosphor-stipple` (7,606 bytes, json_category=advanced-hybrid, json_exists=yes)
- `rgb-split-glitch` (7,600 bytes, json_category=interactive-mouse, json_exists=yes)
- `data-stream-corruption-hdr` (7,588 bytes, json_category=unknown, json_exists=no)
- `fluid-grid-rgba-fluid` (7,508 bytes, json_category=unknown, json_exists=no)
- `oscilloscope-overlay` (7,504 bytes, json_category=interactive-mouse, json_exists=yes)
- `slime-drip` (7,497 bytes, json_category=image, json_exists=yes)
- `snow` (7,487 bytes, json_category=artistic, json_exists=yes)
- `log-polar-droste` (7,410 bytes, json_category=distortion, json_exists=yes)
- `vhs-tracking-bilateral` (7,339 bytes, json_category=advanced-hybrid, json_exists=yes)
- `sim-slime-mold-growth` (7,311 bytes, json_category=simulation, json_exists=yes)
- `crumpled-paper` (7,291 bytes, json_category=image, json_exists=yes)
- `dynamic-lens-flares-prismatic` (7,286 bytes, json_category=unknown, json_exists=no)
- `flow-sort` (7,253 bytes, json_category=simulation, json_exists=yes)
- `quantum-fractal` (7,250 bytes, json_category=artistic, json_exists=yes)
- `flip-matrix` (7,217 bytes, json_category=geometric, json_exists=yes)
- `frost-reveal` (7,204 bytes, json_category=image, json_exists=yes)
- `lidar` (7,193 bytes, json_category=artistic, json_exists=yes)
- `chromatic-reaction-diffusion` (7,186 bytes, json_category=advanced-hybrid, json_exists=yes)
- `retro-phosphor-hdr` (7,178 bytes, json_category=advanced-hybrid, json_exists=yes)
- `radiating-haze` (7,110 bytes, json_category=artistic, json_exists=yes)
- `split-flap-display` (7,062 bytes, json_category=simulation, json_exists=yes)
- `glass-brick-distortion` (7,055 bytes, json_category=distortion, json_exists=yes)
- `time-lag-map` (7,047 bytes, json_category=geometric, json_exists=yes)
- `hybrid-reaction-diffusion-glass` (7,034 bytes, json_category=hybrid, json_exists=yes)
- `cyber-lattice-bilateral` (7,026 bytes, json_category=unknown, json_exists=no)
- `vortex-distortion` (7,018 bytes, json_category=distortion, json_exists=yes)
- `particle-disperse` (6,987 bytes, json_category=interactive-mouse, json_exists=yes)
- `sim-decay-system` (6,986 bytes, json_category=simulation, json_exists=yes)
- `spec-temporal-path-tracer` (6,971 bytes, json_category=advanced-hybrid, json_exists=yes)
- `gravity-lens` (6,885 bytes, json_category=interactive-mouse, json_exists=yes)
- `radiating-displacement` (6,866 bytes, json_category=artistic, json_exists=yes)
- `nano-repair` (6,863 bytes, json_category=interactive-mouse, json_exists=yes)
- `temporal-rgb-ghost` (6,862 bytes, json_category=post-processing, json_exists=yes)
- `audio-reactive-rgb-dispersion` (6,826 bytes, json_category=post-processing, json_exists=yes)
- `temporal_echo` (6,820 bytes, json_category=lighting-effects, json_exists=yes)
- `hyper-chromatic-delay` (6,794 bytes, json_category=interactive-mouse, json_exists=yes)
- `data-stream-corruption` (6,785 bytes, json_category=interactive-mouse, json_exists=yes)
- `charcoal-rub` (6,738 bytes, json_category=interactive-mouse, json_exists=yes)
- `underwater_caustics` (6,738 bytes, json_category=lighting-effects, json_exists=yes)
- `fractal-glass-distort-bilateral` (6,700 bytes, json_category=unknown, json_exists=no)
- `spec-runge-kutta-advection` (6,674 bytes, json_category=simulation, json_exists=yes)
- `temporal-layered-time-stamps` (6,646 bytes, json_category=post-processing, json_exists=yes)
- `sim-sand-dunes` (6,638 bytes, json_category=simulation, json_exists=yes)
- `green-tracer` (6,630 bytes, json_category=artistic, json_exists=yes)
- `energy-shield-blackbody` (6,553 bytes, json_category=unknown, json_exists=no)
- `pixel-wind-chimes` (6,540 bytes, json_category=interactive-mouse, json_exists=yes)
- `particle-swarm` (6,534 bytes, json_category=interactive-mouse, json_exists=yes)
- `digital-decay` (6,529 bytes, json_category=retro-glitch, json_exists=yes)
- `aurora_borealis` (6,509 bytes, json_category=lighting-effects, json_exists=yes)
- `data-stream-structure` (6,467 bytes, json_category=unknown, json_exists=no)
- `nano-assembler` (6,433 bytes, json_category=simulation, json_exists=yes)
- `rgb-distance-split` (6,417 bytes, json_category=visual-effects, json_exists=yes)
- `interactive-origami` (6,363 bytes, json_category=geometric, json_exists=yes)
- `crystalline-shatter` (6,362 bytes, json_category=image, json_exists=yes)
- `navier-stokes-dye` (6,339 bytes, json_category=artistic, json_exists=yes)
- `magnetic-rgb` (6,322 bytes, json_category=interactive-mouse, json_exists=yes)
- `ferrofluid-em` (6,305 bytes, json_category=unknown, json_exists=no)
- `chroma-threads-gabor` (6,205 bytes, json_category=unknown, json_exists=no)
- `digital-glitch-pass2` (6,198 bytes, json_category=retro-glitch, json_exists=yes)
- `plasma` (6,186 bytes, json_category=artistic, json_exists=yes)
- `gamma-ray-burst-blackbody` (6,107 bytes, json_category=unknown, json_exists=no)
- `digital-reveal-guided` (6,096 bytes, json_category=unknown, json_exists=no)
- `interactive-voronoi-web` (6,095 bytes, json_category=interactive-mouse, json_exists=yes)
- `elastic-chromatic-explosion` (6,079 bytes, json_category=unknown, json_exists=no)
- `crt-phosphor-decay` (6,076 bytes, json_category=retro-glitch, json_exists=yes)
- `chroma-lens-iridescence` (6,063 bytes, json_category=unknown, json_exists=no)
- `digital-waves` (6,018 bytes, json_category=retro-glitch, json_exists=yes)
- `bubble-wrap` (5,983 bytes, json_category=interactive-mouse, json_exists=yes)
- `neon-pulse-dissolve` (5,980 bytes, json_category=image, json_exists=yes)
- `data-scanner-gabor` (5,868 bytes, json_category=unknown, json_exists=no)
- `color-channel-weave` (5,854 bytes, json_category=image, json_exists=yes)
- `thermal-vision-blackbody` (5,840 bytes, json_category=advanced-hybrid, json_exists=yes)
- `adaptive-mosaic` (5,820 bytes, json_category=geometric, json_exists=yes)
- `posterize-neon-edges` (5,797 bytes, json_category=image, json_exists=yes)
- `pixel-tornado` (5,792 bytes, json_category=image, json_exists=yes)
- `refractive-bubbles` (5,788 bytes, json_category=interactive-mouse, json_exists=yes)
- `interactive-pcb-traces` (5,777 bytes, json_category=visual-effects, json_exists=yes)
- `sim-heat-haze-field` (5,768 bytes, json_category=simulation, json_exists=yes)
- `digital-lens-prismatic` (5,725 bytes, json_category=unknown, json_exists=no)
- `spec-blue-noise-stipple` (5,655 bytes, json_category=artistic, json_exists=yes)
- `scanline-cyberpunk` (5,610 bytes, json_category=image, json_exists=yes)
- `heat-haze-mirage` (5,599 bytes, json_category=image, json_exists=yes)
- `long-exposure` (5,587 bytes, json_category=post-processing, json_exists=yes)
- `watercolor-bloom` (5,526 bytes, json_category=image, json_exists=yes)
- `interactive-halftone-spin` (5,507 bytes, json_category=interactive-mouse, json_exists=yes)
- `cmyk-halftone-interactive` (5,500 bytes, json_category=interactive-mouse, json_exists=yes)
- `molten-glass` (5,497 bytes, json_category=interactive-mouse, json_exists=yes)
- `kinetic_tiles` (5,430 bytes, json_category=geometric, json_exists=yes)
- `vertical-slice-wave` (5,412 bytes, json_category=interactive-mouse, json_exists=yes)
- `sequin-flip` (5,385 bytes, json_category=interactive-mouse, json_exists=yes)
- `spectrum-bleed` (5,375 bytes, json_category=retro-glitch, json_exists=yes)
- `cyber-rain-interactive` (5,374 bytes, json_category=retro-glitch, json_exists=yes)
- `venetian-blinds` (5,355 bytes, json_category=interactive-mouse, json_exists=yes)
- `cyber-hex-armor` (5,352 bytes, json_category=interactive-mouse, json_exists=yes)
- `ascii-shockwave` (5,338 bytes, json_category=visual-effects, json_exists=yes)
- `oil-slick-iridescence` (5,329 bytes, json_category=image, json_exists=yes)
- `paper-burn` (5,319 bytes, json_category=interactive-mouse, json_exists=yes)
- `magma-fissure` (5,315 bytes, json_category=interactive-mouse, json_exists=yes)
- `voronoi-chaos` (5,300 bytes, json_category=distortion, json_exists=yes)
- `ferrofluid` (5,261 bytes, json_category=interactive-mouse, json_exists=yes)
- `prismatic-3d-compositor` (5,142 bytes, json_category=interactive-mouse, json_exists=yes)
- `sphere-projection` (5,129 bytes, json_category=interactive-mouse, json_exists=yes)
- `chroma-depth-tunnel-prismatic` (5,113 bytes, json_category=unknown, json_exists=no)
- `thermal-touch-blackbody` (5,017 bytes, json_category=advanced-hybrid, json_exists=yes)
- `liquid-optimized-pass2` (4,977 bytes, json_category=liquid-effects, json_exists=yes)
- `cyber-magnifier` (4,966 bytes, json_category=interactive-mouse, json_exists=yes)
- `fractal-kaleidoscope` (4,962 bytes, json_category=distortion, json_exists=yes)
- `quantum-superposition` (4,935 bytes, json_category=interactive-mouse, json_exists=yes)
- `cross-conv-mouse-bilateral` (4,920 bytes, json_category=image, json_exists=yes)
- `sim-fluid-feedback-field-pass1` (4,897 bytes, json_category=unknown, json_exists=no)
- `luma-refraction` (4,876 bytes, json_category=image, json_exists=yes)
- `rain-lens-wipe` (4,851 bytes, json_category=interactive-mouse, json_exists=yes)
- `pixel-explode` (4,834 bytes, json_category=interactive-mouse, json_exists=yes)
- `reaction-diffusion` (4,830 bytes, json_category=artistic, json_exists=yes)
- `cursor-aura` (4,774 bytes, json_category=interactive-mouse, json_exists=yes)
- `pixel-storm` (4,757 bytes, json_category=distortion, json_exists=yes)
- `digital-reveal` (4,756 bytes, json_category=interactive-mouse, json_exists=yes)
- `tone-histogram-apply` (4,693 bytes, json_category=post-processing, json_exists=yes)
- `voronoi-glass` (4,674 bytes, json_category=interactive-mouse, json_exists=yes)
- `radial-hex-lens` (4,464 bytes, json_category=interactive-mouse, json_exists=yes)
- `cyber-trace` (4,459 bytes, json_category=interactive-mouse, json_exists=yes)
- `moire-interference` (4,459 bytes, json_category=interactive-mouse, json_exists=yes)
- `rainbow-vector-field` (4,457 bytes, json_category=interactive-mouse, json_exists=yes)
- `speed-lines-focus` (4,450 bytes, json_category=artistic, json_exists=yes)
- `chroma-lens` (4,441 bytes, json_category=interactive-mouse, json_exists=yes)
- `cyber-focus` (4,429 bytes, json_category=interactive-mouse, json_exists=yes)
- `scanline-drift` (4,425 bytes, json_category=retro-glitch, json_exists=yes)
- `sim-fluid-feedback-field-pass2` (4,416 bytes, json_category=unknown, json_exists=no)

### JSON

- `tensor-flow-sculpt` (17,667 bytes, json_category=unknown, json_exists=no)
- `spectral-bleed-confine` (16,307 bytes, json_category=unknown, json_exists=no)
- `gen-bioluminescent-abyss` (14,687 bytes, json_category=unknown, json_exists=no)
- `gen-alien-flora-ecosystem` (12,405 bytes, json_category=unknown, json_exists=no)
- `gen_trails` (12,051 bytes, json_category=generative, json_exists=yes)
- `gen-art-deco-sky-prismatic` (11,854 bytes, json_category=unknown, json_exists=no)
- `gen_grok4_perlin` (11,492 bytes, json_category=generative, json_exists=yes)
- `gen-bismuth-citadel-crystal` (10,589 bytes, json_category=unknown, json_exists=no)
- `gen_fluffy_raincloud` (10,395 bytes, json_category=generative, json_exists=yes)
- `gen_rainbow_smoke` (10,220 bytes, json_category=generative, json_exists=yes)
- `gen_grid` (10,147 bytes, json_category=generative, json_exists=yes)
- `gen_orb` (10,062 bytes, json_category=generative, json_exists=yes)
- `gen_grok41_plasma` (9,996 bytes, json_category=generative, json_exists=yes)
- `liquid-jelly-fluid` (9,724 bytes, json_category=unknown, json_exists=no)
- `cosmic-web-structure` (9,705 bytes, json_category=unknown, json_exists=no)
- `gen_grokcf_voronoi` (9,689 bytes, json_category=generative, json_exists=yes)
- `gen-string-theory-structure` (9,615 bytes, json_category=unknown, json_exists=no)
- `gen-abyssal-leviathan-iridescence` (9,613 bytes, json_category=unknown, json_exists=no)
- `gen_grokcf_interference` (9,537 bytes, json_category=generative, json_exists=yes)
- `cosmic-jellyfish-coupled` (9,527 bytes, json_category=unknown, json_exists=no)
- `kimi-flock-symphony-em` (9,485 bytes, json_category=unknown, json_exists=no)
- `gen_grok41_mandelbrot` (9,213 bytes, json_category=generative, json_exists=yes)
- `gen_kimi_crystal` (9,060 bytes, json_category=generative, json_exists=yes)
- `cyber-organic-ecosystem` (9,030 bytes, json_category=unknown, json_exists=no)
- `frost-reveal-crystal` (8,979 bytes, json_category=unknown, json_exists=no)
- `liquid-smear-structure` (8,898 bytes, json_category=unknown, json_exists=no)
- `hyperbolic-dreamweaver-julia` (8,895 bytes, json_category=unknown, json_exists=no)
- `ethereal-swirl-coupled` (8,747 bytes, json_category=unknown, json_exists=no)
- `crystal-illuminator-iridescence` (8,737 bytes, json_category=unknown, json_exists=no)
- `impasto-swirl-bilateral` (8,736 bytes, json_category=unknown, json_exists=no)
- `gen_grok4_life` (8,714 bytes, json_category=generative, json_exists=yes)
- `cyber-trace-structure` (8,672 bytes, json_category=unknown, json_exists=no)
- `gravity-well-em` (8,627 bytes, json_category=unknown, json_exists=no)
- `bismuth-crystal-growth` (8,626 bytes, json_category=unknown, json_exists=no)
- `chromatic-folds-bilateral` (8,611 bytes, json_category=unknown, json_exists=no)
- `gen-singularity-forge-blackbody` (8,566 bytes, json_category=unknown, json_exists=no)
- `astral-kaleidoscope-julia` (8,537 bytes, json_category=unknown, json_exists=no)
- `liquid-rainbow-prismatic` (8,519 bytes, json_category=unknown, json_exists=no)
- `gen_reaction_diffusion` (8,426 bytes, json_category=generative, json_exists=yes)
- `anamorphic-flare-iridescence` (8,397 bytes, json_category=unknown, json_exists=no)
- `liquid-oil-iridescence` (8,308 bytes, json_category=unknown, json_exists=no)
- `ink-bleed-fluid` (8,212 bytes, json_category=unknown, json_exists=no)
- `gen-neural-fractal-hdr` (8,144 bytes, json_category=unknown, json_exists=no)
- `digital-glitch-explosion` (8,084 bytes, json_category=unknown, json_exists=no)
- `gemstone-fractures-crystal` (7,997 bytes, json_category=unknown, json_exists=no)
- `kimi_ripple_touch` (7,950 bytes, json_category=interactive-mouse, json_exists=yes)
- `viscous-drag-bilateral` (7,946 bytes, json_category=unknown, json_exists=no)
- `chromatic-focus-guided` (7,942 bytes, json_category=unknown, json_exists=no)
- `chromatic-crawler-structure` (7,845 bytes, json_category=unknown, json_exists=no)
- `distortion-gravitational-prismatic` (7,837 bytes, json_category=unknown, json_exists=no)
- `infinite-fractal-feedback-hdr` (7,817 bytes, json_category=unknown, json_exists=no)
- `data-stream-corruption-hdr` (7,588 bytes, json_category=unknown, json_exists=no)
- `gen_julia_set` (7,579 bytes, json_category=generative, json_exists=yes)
- `frosted-glass-lens-iridescence` (7,517 bytes, json_category=unknown, json_exists=no)
- `fluid-grid-rgba-fluid` (7,508 bytes, json_category=unknown, json_exists=no)
- `interactive-origami-coupled` (7,459 bytes, json_category=unknown, json_exists=no)
- `vortex-warp-coupled` (7,403 bytes, json_category=unknown, json_exists=no)
- `gen_hyper_warp` (7,395 bytes, json_category=generative, json_exists=yes)
- `interactive-magnetic-ripple-em` (7,306 bytes, json_category=unknown, json_exists=no)
- `chronos-brush-explosion` (7,297 bytes, json_category=unknown, json_exists=no)
- `dynamic-lens-flares-prismatic` (7,286 bytes, json_category=unknown, json_exists=no)
- `cyber-scan-gabor` (7,281 bytes, json_category=unknown, json_exists=no)
- `galaxy` (7,265 bytes, json_category=artistic, json_exists=yes)
- `digital-moss-rgba` (7,245 bytes, json_category=unknown, json_exists=no)
- `gen_kimi_nebula` (7,231 bytes, json_category=generative, json_exists=yes)
- `dimension-slicer-guided` (7,201 bytes, json_category=unknown, json_exists=no)
- `cyber-rain-em` (7,199 bytes, json_category=unknown, json_exists=no)
- `steamy-glass-volumetric` (7,188 bytes, json_category=unknown, json_exists=no)
- `honey-melt-blackbody` (7,176 bytes, json_category=unknown, json_exists=no)
- `melting-oil-blackbody` (7,174 bytes, json_category=unknown, json_exists=no)
- `chroma-vortex-coupled` (7,161 bytes, json_category=unknown, json_exists=no)
- `heat-haze-volumetric` (7,133 bytes, json_category=unknown, json_exists=no)
- `kimi_fractal_dreams` (7,119 bytes, json_category=generative, json_exists=yes)
- `cursor-aura-explosion` (7,106 bytes, json_category=unknown, json_exists=no)
- `gen-quasicrystal-iridescence` (7,097 bytes, json_category=unknown, json_exists=no)
- `gen_cyclic_automaton` (7,043 bytes, json_category=generative, json_exists=yes)
- `vaporwave-horizon-prismatic` (7,038 bytes, json_category=unknown, json_exists=no)
- `cyber-lattice-bilateral` (7,026 bytes, json_category=unknown, json_exists=no)
- `interactive-pixel-wind-structure` (7,006 bytes, json_category=unknown, json_exists=no)
- `kimi_nebula_depth` (6,999 bytes, json_category=generative, json_exists=yes)
- `fire-smoke-volumetric-fog` (6,992 bytes, json_category=unknown, json_exists=no)
- `kimi_quantum_field` (6,918 bytes, json_category=generative, json_exists=yes)
- `breathing-kaleidoscope-morph` (6,845 bytes, json_category=unknown, json_exists=no)
- `gen_wave_equation` (6,783 bytes, json_category=generative, json_exists=yes)
- `edge-glow-mouse-em` (6,772 bytes, json_category=unknown, json_exists=no)
- `fractal-glass-distort-bilateral` (6,700 bytes, json_category=unknown, json_exists=no)
- `gen_psychedelic_spiral` (6,664 bytes, json_category=generative, json_exists=yes)
- `energy-shield-blackbody` (6,553 bytes, json_category=unknown, json_exists=no)
- `cyber-ripples-coupled` (6,534 bytes, json_category=unknown, json_exists=no)
- `fractal-noise-dissolve-nlm` (6,485 bytes, json_category=unknown, json_exists=no)
- `divine-light-iridescence` (6,482 bytes, json_category=unknown, json_exists=no)
- `data-stream-structure` (6,467 bytes, json_category=unknown, json_exists=no)
- `hyper-space-jump-blackbody` (6,441 bytes, json_category=unknown, json_exists=no)
- `phantom-lag-history` (6,384 bytes, json_category=unknown, json_exists=no)
- `warp-drive-blackbody` (6,332 bytes, json_category=unknown, json_exists=no)
- `ferrofluid-em` (6,305 bytes, json_category=unknown, json_exists=no)
- `graphic_novel` (6,216 bytes, json_category=image, json_exists=yes)
- `chroma-threads-gabor` (6,205 bytes, json_category=unknown, json_exists=no)
- `chroma-kinetic-blackbody` (6,120 bytes, json_category=unknown, json_exists=no)
- `gamma-ray-burst-blackbody` (6,107 bytes, json_category=unknown, json_exists=no)
- `digital-reveal-guided` (6,096 bytes, json_category=unknown, json_exists=no)
- `elastic-chromatic-explosion` (6,079 bytes, json_category=unknown, json_exists=no)
- `warp_drive` (6,067 bytes, json_category=visual-effects, json_exists=yes)
- `chroma-lens-iridescence` (6,063 bytes, json_category=unknown, json_exists=no)
- `data-stream-spectral` (5,885 bytes, json_category=unknown, json_exists=no)
- `data-scanner-gabor` (5,868 bytes, json_category=unknown, json_exists=no)
- `interactive-rgb-split-explosion` (5,785 bytes, json_category=unknown, json_exists=no)
- `digital-lens-prismatic` (5,725 bytes, json_category=unknown, json_exists=no)
- `kimi_liquid_glass` (5,722 bytes, json_category=liquid-effects, json_exists=yes)
- `lorenz-attractor-flow` (5,631 bytes, json_category=unknown, json_exists=no)
- `brush-strokes` (5,572 bytes, json_category=unknown, json_exists=no)
- `pixelate-blast` (5,528 bytes, json_category=unknown, json_exists=no)
- `kinetic_tiles` (5,430 bytes, json_category=geometric, json_exists=yes)
- `kimi_chromatic_warp` (5,227 bytes, json_category=interactive-mouse, json_exists=yes)
- `chroma-depth-tunnel-prismatic` (5,113 bytes, json_category=unknown, json_exists=no)
- `sim-fluid-feedback-field-pass3` (4,957 bytes, json_category=unknown, json_exists=no)
- `sim-fluid-feedback-field-pass1` (4,897 bytes, json_category=unknown, json_exists=no)
- `kimi_spotlight` (4,453 bytes, json_category=interactive-mouse, json_exists=yes)
- `sim-fluid-feedback-field-pass2` (4,416 bytes, json_category=unknown, json_exists=no)
- `ring_slicer` (3,574 bytes, json_category=image, json_exists=yes)

### WORKGROUP

- `deep-workgroup-multi-effect-blend` (10,777 bytes, json_category=advanced-hybrid, json_exists=yes)
